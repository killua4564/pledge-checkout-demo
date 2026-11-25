require "application_system_test_case"

# I. 畫面流程（I1「版面」需要人眼確認，不在這裡）
class CheckoutTest < ApplicationSystemTestCase
  setup do
    @project = create_project(slug: "mountain-map")
    @reward = create_reward(project: @project, price: 2980, quota_total: 200, quota_taken: 190)
    @addon = create_addon(project: @project, price: 300, title: "加購小物")
    create_code(project: @project, code: "SAVE500", amount: 500)
  end

  def visit_checkout(reward = @reward)
    visit project_checkout_path(@project, reward: reward.id)
    assert_text "使用折扣碼"
  end

  def total = find("[data-testid=total]")

  def fill_in_recipient
    select "新北市", from: "checkout_ship_city"
    select "新莊區", from: "checkout_ship_district"
    fill_in "checkout_ship_address", with: "中正路 1 號"
    fill_in "checkout_recipient_name", with: "王小明"
    fill_in "checkout_recipient_phone", with: "0912345678"
  end

  test "I2 勾選加購、輸入折扣碼、切換地區、加碼 → 金額即時更新" do
    visit_checkout
    assert_equal "NT$ 2,980", total.text

    check "加購小物"
    assert_selector "[data-testid=total]", text: "NT$ 3,280"

    fill_in "checkout_discount_code", with: "save500"
    assert_selector "[data-testid=total]", text: "NT$ 2,780"

    select "台灣（離島）", from: "checkout_ship_region"
    assert_selector "[data-testid=total]", text: "NT$ 2,910"   # 運費 100 + 加購運費 30

    fill_in "checkout_donation", with: "70"
    assert_selector "[data-testid=total]", text: "NT$ 2,980"
  end

  test "I3 縣市 → 鄉鎮市區 → 郵遞區號連動；海外時隱藏縣市" do
    visit_checkout
    select "桃園市", from: "checkout_ship_city"
    select "中壢區", from: "checkout_ship_district"
    assert_field "checkout_ship_zip", with: "320"

    select "海外", from: "checkout_ship_region"
    assert_no_selector "#checkout_ship_city", visible: true
  end

  test "I4 個人／公司發票切換" do
    visit_checkout
    assert_selector "#checkout_carrier_code", visible: true
    assert_no_selector "#checkout_company_tax_id", visible: true

    choose "checkout_invoice_type_company"
    assert_selector "#checkout_company_tax_id", visible: true
    assert_no_selector "#checkout_carrier_code", visible: true
  end

  test "I5 信用卡付款成功：假金流 → 處理中 → 完成頁" do
    visit_checkout
    check "加購小物"
    fill_in_recipient
    click_on "確認付款"

    assert_text "信用卡付款"            # 假金流頁
    assert_text "NT$ 3,280"
    click_on "付款成功"

    assert_text "贊助成功！"
    assert_equal "paid", Order.last.status
  end

  test "I6 信用卡付款失敗：失敗頁有重新結帳，名額回補" do
    visit_checkout
    fill_in_recipient
    click_on "確認付款"
    click_on "付款失敗"

    assert_text "付款失敗"
    assert_equal 190, @reward.reload.quota_taken
    click_on "重新結帳"
    assert_text "使用折扣碼"
  end

  test "I7 ATM 付款成功：顯示虛擬帳號 → 模擬轉帳 → 完成頁" do
    visit_checkout
    choose "checkout_payment_method_atm"
    fill_in_recipient
    click_on "確認付款"

    assert_text "請於期限內完成轉帳"
    assert_selector "[data-testid=virtual-account]"
    click_on "前往假金流：模擬 ATM 轉帳"
    click_on "模擬已轉帳"
    assert_text "贊助成功！"
  end

  test "I8 ATM 逾期：執行逾期處理後顯示已過期，名額回補" do
    visit_checkout
    choose "checkout_payment_method_atm"
    fill_in_recipient
    click_on "確認付款"
    assert_text "請於期限內完成轉帳"

    Orders::ExpireOverdue.call(now: 4.days.from_now)
    visit order_path(Order.last)
    assert_text "訂單已過期"
    assert_equal 190, @reward.reload.quota_taken
  end

  test "I9 callback 晚到：頁面先顯示處理中，callback 到了自動更新" do
    visit_checkout
    fill_in_recipient
    click_on "確認付款"
    assert_text "信用卡付款"

    # 先不送 callback，模擬金流通知還沒到
    stub_method(DeliverFakeCallbackJob, :perform_later, ->(*, **) {}) do
      click_on "付款成功"
      assert_text "付款處理中"
    end

    deliver_callback(Order.last.latest_payment, status: "success")
    assert_text "贊助成功！", wait: 6         # 輪詢會自動重新整理
  end

  test "I10 取消待付款訂單" do
    visit_checkout
    choose "checkout_payment_method_atm"
    fill_in_recipient
    click_on "確認付款"
    accept_confirm { click_on "取消訂單" }
    assert_text "訂單已取消"
  end

  test "I11 0 元訂單直接到完成頁" do
    early = create_reward(project: @project, price: 800, title: "早鳥單本")
    create_code(project: @project, code: "FREE800", amount: 800)
    visit_checkout(early)
    fill_in "checkout_discount_code", with: "FREE800"
    assert_selector "[data-testid=total]", text: "NT$ 0"
    fill_in_recipient
    click_on "確認付款"
    assert_text "贊助成功！"
  end

  test "I12 選方案 → 結帳 → 更改回饋 → 回到選方案頁" do
    visit project_rewards_path(@project)
    assert_text "選擇回饋方案"
    click_on "選擇此方案"
    assert_text "使用折扣碼"
    click_on "更改回饋"
    assert_text "選擇回饋方案"
  end

  test "I13 在完成頁重新整理：不會重複建立訂單" do
    visit_checkout
    fill_in_recipient
    click_on "確認付款"
    click_on "付款成功"
    assert_text "贊助成功！"

    refresh
    assert_text "贊助成功！"
    assert_equal 1, Order.count
  end
end
