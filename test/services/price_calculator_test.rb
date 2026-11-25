require "test_helper"

# A. 金額計算（docs/test-plan.md）
class PriceCalculatorTest < ActiveSupport::TestCase
  setup do
    @project = create_project
    @bundle = create_reward(project: @project, price: 2980)
    @addon = create_addon(project: @project, price: 300, title: "加購小物")
    @bookmark = create_addon(project: @project, price: 100, title: "書籤組")
    create_code(project: @project, code: "SAVE500", amount: 500)
  end

  def quote(reward = @bundle, **args) = Checkout::PriceCalculator.call(reward: reward, **args)

  test "A1 不選加購、不用折扣碼、本島：總額就是方案金額" do
    assert_equal 2980, quote.total_amount
  end

  test "A2 方案 2980 + 加購 300 = 3280" do
    assert_equal 3280, quote(addon_ids: [@addon.id]).total_amount
  end

  test "A3 不選加購，用 SAVE500：2980 − 500 = 2480" do
    q = quote(discount_code: "SAVE500")
    assert_equal 500, q.discount_amount
    assert_equal 2480, q.total_amount
  end

  test "A4 有加購也用 SAVE500：只折方案金額，2980 + 300 − 500 = 2780" do
    q = quote(addon_ids: [@addon.id], discount_code: "SAVE500")
    assert_equal 500, q.discount_amount
    assert_equal 2780, q.total_amount
  end

  test "A5 選多個不同加購：加總，且加購運費只加一次" do
    q = quote(addon_ids: [@addon.id, @bookmark.id], region: "tw_island")
    assert_equal 400, q.addons_amount
    assert_equal 130, q.shipping_amount
  end

  test "A6 同一個加購 ID 重複送出只算一次" do
    assert_equal 300, quote(addon_ids: [@addon.id, @addon.id.to_s]).addons_amount
  end

  test "A7 加購屬於其他專案或不存在：拒絕" do
    other = create_addon(project: create_project, price: 999)
    refute quote(addon_ids: [other.id]).valid?
    refute quote(addon_ids: [999_999]).valid?
  end

  test "A8 同專案的不同方案都能選同一批加購" do
    early = create_reward(project: @project, price: 800, title: "早鳥單本")
    assert quote(early, addon_ids: [@addon.id]).valid?
    assert quote(@bundle, addon_ids: [@addon.id]).valid?
  end

  test "A9 離島運費 100；有加購再加 30" do
    assert_equal 130, quote(addon_ids: [@addon.id], region: "tw_island").shipping_amount
    assert_equal 100, quote(region: "tw_island").shipping_amount
  end

  test "A10 海外運費依 shipping_rates" do
    assert_equal 300, quote(region: "overseas").shipping_amount
    assert_equal 350, quote(region: "overseas", addon_ids: [@addon.id]).shipping_amount
  end

  test "A11 地區不存在：拒絕" do
    refute quote(region: "moon").valid?
  end

  test "A12 加碼贊助 500：總額加 500" do
    assert_equal 3480, quote(donation: "500").total_amount
  end

  test "A13 加碼贊助是負數、文字、超過上限、TWD 帶小數：拒絕" do
    ["-1", "abc", "100001", "10.5"].each do |input|
      refute quote(donation: input).valid?, "#{input.inspect} 應該被拒絕"
    end
  end

  test "A14 加碼贊助空白視為 0" do
    q = quote(donation: "")
    assert q.valid?
    assert_equal 0, q.donation_amount
  end

  test "A15 折扣碼不存在：顯示原因、折扣 0、不丟例外" do
    q = quote(discount_code: "NOPE")
    assert_equal 0, q.discount_amount
    assert_match "不存在", q.discount_error
  end

  test "A16 折扣碼已過期或尚未開始：無效" do
    create_code(project: @project, code: "OLD", ends_at: 1.day.ago)
    create_code(project: @project, code: "SOON", starts_at: 1.day.from_now)
    assert_match "有效期間", quote(discount_code: "OLD").discount_error
    assert_match "有效期間", quote(discount_code: "SOON").discount_error
  end

  test "A17 用其他專案的折扣碼：無效" do
    create_code(project: create_project, code: "GAME100", amount: 100)
    q = quote(discount_code: "GAME100")
    assert_equal 0, q.discount_amount
    assert q.discount_error
  end

  test "A18 折扣碼不分大小寫、忽略前後空白" do
    assert_equal 500, quote(discount_code: " save500 ").discount_amount
  end

  test "A19 折扣金額大於方案金額：最多折到方案金額，不會變負數" do
    early = create_reward(project: @project, price: 300, title: "便宜方案")
    q = quote(early, discount_code: "SAVE500")
    assert_equal 300, q.discount_amount
    assert_equal 0, q.total_amount
  end

  test "A20 剛好折到 0 元" do
    early = create_reward(project: @project, price: 800, title: "早鳥單本")
    create_code(project: @project, code: "FREE800", amount: 800)
    q = quote(early, discount_code: "FREE800")
    assert_equal 0, q.total_amount
    assert q.free?
  end

  test "A21 方案折到 0，但有加購與運費：總額 = 加購 + 運費" do
    early = create_reward(project: @project, price: 300, title: "便宜方案")
    q = quote(early, discount_code: "SAVE500", addon_ids: [@addon.id], region: "tw_island")
    assert_equal 300 + 130, q.total_amount
  end

  test "A22 隨機組合：總額一律 >= 0，折扣一律 <= 方案金額" do
    rng = Random.new(42)
    50.times do
      reward = create_reward(project: @project, price: rng.rand(1..3000), title: "隨機")
      create_code(project: @project, code: "R#{SecureRandom.hex(3)}", amount: rng.rand(1..5000)).then do |code|
        q = quote(reward, discount_code: code.code,
                          addon_ids: [@addon, @bookmark].sample(rng.rand(0..2), random: rng).map(&:id),
                          region: %w[tw_main tw_island overseas].sample(random: rng),
                          donation: rng.rand(0..1000).to_s)
        assert q.total_amount >= 0
        assert q.discount_amount <= reward.price
      end
    end
  end

  test "A25 預覽與下單使用同一個計算器，同輸入同結果" do
    order = place_order!(@bundle, addon_ids: [@addon.id.to_s], discount_code: "SAVE500", donation: "200")
    q = quote(addon_ids: [@addon.id], discount_code: "SAVE500", donation: "200")
    assert_equal q.total_amount, order.total_amount
  end

  test "A26 USD 依幣別保留 2 位小數：19.99 + 加碼 0.5 = 20.49" do
    usd_project = create_project(currency: "USD")
    reward = create_reward(project: usd_project, price: BigDecimal("19.99"))
    q = quote(reward, donation: "0.5")
    assert_equal BigDecimal("20.49"), q.total_amount
    assert_equal "US$ 20.49", q.money(q.total_amount)
  end

  test "A27 所有金額都是 BigDecimal，沒有 float" do
    q = quote(addon_ids: [@addon.id], discount_code: "SAVE500", donation: "1")
    %i[reward_amount addons_amount discount_amount shipping_amount donation_amount total_amount].each do |field|
      assert_kind_of BigDecimal, q.public_send(field), "#{field} 應該是 BigDecimal"
    end
  end
end
