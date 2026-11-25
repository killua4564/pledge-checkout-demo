require "test_helper"

# C. 建立訂單與驗證、H. 讀寫分離、J. 0 元訂單，以及 A23、A24、E17（需要走完整 HTTP 請求的測項）
class CheckoutFlowTest < ActionDispatch::IntegrationTest
  setup do
    @project = create_project(slug: "mountain-map")
    @reward = create_reward(project: @project, price: 2980, quota_total: 200, quota_taken: 190)
    @addon = create_addon(project: @project, price: 300)
    create_code(project: @project, code: "SAVE500", amount: 500)
  end

  def submit(**overrides)
    post orders_path, params: { checkout: checkout_params(@reward, **overrides) }
  end

  # ── C. 建立訂單 ──

  test "C1 信用卡：建立待付款訂單與付款紀錄，導向假金流，名額 +1" do
    assert_difference -> { Order.count } => 1, -> { Payment.count } => 1 do
      submit
    end
    order = Order.last
    assert_equal "pending_payment", order.status
    assert_redirected_to fake_gateway_pay_path(order.latest_payment.provider_trade_no)
    assert_equal 191, @reward.reload.quota_taken
    assert_in_delta 15.minutes.from_now, order.expires_at, 5
  end

  test "C2 ATM：產生虛擬帳號與繳費期限，導向訂單頁" do
    submit(payment_method: "atm")
    order = Order.last
    payment = order.latest_payment
    assert_redirected_to order_path(order)
    assert_match(/\A\d{14}\z/, payment.virtual_account)
    assert_equal order.expires_at, payment.pay_deadline
    follow_redirect!
    assert_select "[data-testid=virtual-account]", payment.virtual_account
  end

  test "C3 繞過畫面限制送出 aftee：422 尚未開放，不建單、不扣名額" do
    assert_no_difference -> { Order.count } do
      submit(payment_method: "aftee")
    end
    assert_response :unprocessable_entity
    assert_match "尚未開放", response.body
    assert_equal 190, @reward.reload.quota_taken
  end

  test "C4 不存在的付款方式：422" do
    submit(payment_method: "bitcoin")
    assert_response :unprocessable_entity
  end

  test "C5 必填欄位缺漏、電話格式錯誤：422，並保留已填資料" do
    submit(recipient_name: "", recipient_phone: "12345", ship_address: "保留這段地址")
    assert_response :unprocessable_entity
    assert_match "請填寫收件人", response.body
    assert_match "10 碼手機", response.body
    assert_select "input[name='checkout[ship_address]'][value=?]", "保留這段地址"
  end

  test "C6 手機載具：/AB1CD23 通過、格式錯誤擋下、空白通過" do
    submit(carrier_code: "/AB1CD23")
    assert_response :see_other
    submit(carrier_code: "AB1CD23")
    assert_response :unprocessable_entity
    submit(carrier_code: "/AB1")
    assert_response :unprocessable_entity
    submit(carrier_code: "")
    assert_response :see_other
  end

  test "C7 公司發票缺統編或抬頭、統編不是 8 碼：422" do
    submit(invoice_type: "company", company_tax_id: "", company_title: "")
    assert_response :unprocessable_entity
    submit(invoice_type: "company", company_tax_id: "1234", company_title: "範例公司")
    assert_response :unprocessable_entity
    submit(invoice_type: "company", company_tax_id: "12345678", company_title: "範例公司")
    assert_response :see_other
  end

  test "C8 同一個 checkout_token 送出兩次：只有一張訂單" do
    params = checkout_params(@reward)
    assert_difference -> { Order.count } => 1 do
      2.times { post orders_path, params: { checkout: params } }
    end
    assert_equal 191, @reward.reload.quota_taken
  end

  test "C9 下單時折扣碼無效：422，不建立訂單" do
    assert_no_difference -> { Order.count } do
      submit(discount_code: "NOPE")
    end
    assert_response :unprocessable_entity
    assert_match "折扣碼不存在", response.body
  end

  test "C10 方案不存在、或方案屬於其他專案：404；沒帶方案：回選方案頁" do
    get project_checkout_path(@project)
    assert_redirected_to project_rewards_path(@project)

    get project_checkout_path(@project, reward: 999_999)
    assert_response :not_found

    other = create_reward(project: create_project)
    get project_checkout_path(@project, reward: other.id)
    assert_response :not_found
  end

  test "C11 首頁輸入方案 ID：存在就到結帳頁，其他回首頁並提示" do
    get go_path(reward_id: @reward.id)
    assert_redirected_to project_checkout_path(@project, reward: @reward.id)

    get go_path(reward_id: "999999")
    assert_redirected_to root_path(error: "not_found")
    get go_path(reward_id: "abc")
    assert_redirected_to root_path(error: "not_found")
    get go_path(reward_id: "")
    assert_redirected_to root_path(error: "blank")

    follow_redirect!
    assert_match "請輸入方案 ID", response.body
  end

  test "C12 public_id 是 UUID，網址用它而不是流水號" do
    submit
    order = Order.last
    assert_match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, order.public_id)
    get "/orders/#{order.id}"
    assert_response :not_found
  end

  test "C13 使用折扣碼：建立一筆 order_discounts，同一張訂單不能有第二筆" do
    submit(discount_code: "save500")
    order = Order.last
    assert_equal ["SAVE500", 500], [order.order_discount.code, order.order_discount.amount]
    assert_raises(ActiveRecord::RecordNotUnique) do
      OrderDiscount.create!(order: order, discount_code: order.order_discount.discount_code, code: "SAVE500", amount: 1)
    end
  end

  test "名額已滿：422，不建立訂單" do
    @reward.update!(quota_taken: 200)
    assert_no_difference -> { Order.count } do
      submit
    end
    assert_response :unprocessable_entity
    assert_match "名額已經被搶完", response.body
  end

  # ── A23、A24、E17 ──

  test "A23 表單偷塞 total、price 等金額欄位：完全忽略，以伺服器計算為準" do
    post orders_path, params: { checkout: checkout_params(@reward).merge(total_amount: "1", price: "1", reward_amount: "1") }
    assert_equal 2980, Order.last.total_amount
  end

  test "A24 方案改價後，舊訂單金額不變（快照）" do
    submit(addon_ids: [@addon.id])
    order = Order.last
    @reward.update!(price: 9999)
    @addon.update!(price: 9999)
    assert_equal 3280, order.reload.total_amount
    assert_equal 300, order.order_addons.first.price
  end

  test "E17 瀏覽器直接造訪訂單頁並帶 status=paid：狀態不變" do
    submit
    order = Order.last
    get order_path(order, status: "paid")
    assert_equal "pending_payment", order.reload.status
    assert_match "付款處理中", response.body
  end

  # ── J. 0 元訂單 ──

  test "J1–J4 0 元訂單：不建 payment、不經金流，直接轉 paid；有扣名額、記錄折扣與轉換原因" do
    early = create_reward(project: @project, price: 800, title: "早鳥單本")
    create_code(project: @project, code: "FREE800", amount: 800)

    assert_no_difference -> { Payment.count } do
      post orders_path, params: { checkout: checkout_params(early, discount_code: "FREE800", payment_method: "atm") }
    end
    order = Order.last
    assert_redirected_to order_path(order)
    assert_equal "paid", order.status
    assert_equal "free", order.payment_method                          # J4 忽略使用者選的 ATM
    assert_equal 1, early.reload.quota_taken                           # J2 有扣名額
    assert_equal "FREE800", order.order_discount.code                  # J2 有記錄折扣
    assert_equal "金額為 0，免付款", order.order_transitions.last.reason  # J3
    follow_redirect!
    assert_match "贊助成功", response.body
  end

  # ── 取消訂單 ──

  test "使用者取消待付款訂單：轉 cancelled，名額釋放；已付款的訂單不能取消" do
    submit(payment_method: "atm")
    order = Order.last
    post cancel_order_path(order)
    assert_equal "cancelled", order.reload.status
    assert_equal 190, @reward.reload.quota_taken

    submit
    paid = Order.last
    Orders::Transition.call(paid, :pay, reason: "測試")
    post cancel_order_path(paid)
    assert_equal "paid", paid.reload.status
  end

  # ── H. 讀寫分離 ──
  # 測試環境預設關閉 CSRF 保護（頁面不會輸出 token），這組測試要暫時打開才驗得出差別
  def with_forgery_protection
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  test "H1 專案頁、選方案頁、首頁：可公開快取，沒有 Set-Cookie、沒有 CSRF token" do
    with_forgery_protection do
      [root_path, project_path(@project), project_rewards_path(@project)].each do |path|
        get path
        assert_response :success
        assert_nil response.headers["Set-Cookie"], "#{path} 不應該設定 cookie"
        assert_match "public", response.headers["Cache-Control"], "#{path} 應該可以公開快取"
        assert_match "s-maxage=300", response.headers["Cache-Control"]
        assert_no_match "csrf-token", response.body
      end
    end
  end

  test "H2 結帳頁、訂單頁：不可快取；結帳頁有 CSRF token" do
    with_forgery_protection do
      get project_checkout_path(@project, reward: @reward.id)
      assert_equal "no-store", response.headers["Cache-Control"]
      assert_match "csrf-token", response.body
    end

    submit
    get order_path(Order.last)
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "H3 剩餘名額端點：回傳數字，快取時間很短" do
    get reward_stock_path(@reward)
    assert_equal 10, response.parsed_body["remaining"]
    assert_match "s-maxage=5", response.headers["Cache-Control"]
  end

  test "H5 訂單頁自動更新：只有信用卡待付款時輪詢，ATM 改成手動重新整理" do
    submit(payment_method: "credit_card")
    get order_path(Order.last)
    assert_select "[data-controller=poll]", 1

    submit(payment_method: "atm")
    get order_path(Order.last)
    assert_select "[data-controller=poll]", 0
    assert_select "a", text: "重新整理"
  end

  test "H4 讀取頁面不寫入資料庫" do
    writes = []
    callback = ->(*, payload) { writes << payload[:sql] if payload[:sql].match?(/\A\s*(INSERT|UPDATE|DELETE)/i) }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      get project_path(@project)
      get project_rewards_path(@project)
      get reward_stock_path(@reward)
    end
    assert_empty writes
  end

  # ── 即時金額預覽 ──

  test "金額預覽：回傳新的金額區塊，與下單計算一致" do
    post checkout_quote_path, params: { checkout: { reward_id: @reward.id, addon_ids: [@addon.id], discount_code: "SAVE500" } },
                              headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_match "NT$ 2,780", response.body
  end
end
