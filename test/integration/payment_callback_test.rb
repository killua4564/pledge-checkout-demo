require "test_helper"

# E. Callback：簽章、重複通知、金額不符、順序錯亂、逾期才付款
# 這裡用真的 HTTP POST 打 /payments/callbacks/fake，和金流實際呼叫的方式一樣
class PaymentCallbackTest < ActionDispatch::IntegrationTest
  setup do
    @reward = create_reward(quota_total: 10)
    @order = place_order!(@reward)
    @payment = @order.latest_payment
  end

  def post_callback(body, headers)
    post payment_callback_path(provider: "fake"), params: body,
                                                  headers: headers.merge("CONTENT_TYPE" => "application/json")
  end

  def callback!(**options)
    post_callback(*signed_callback(@payment, **options))
  end

  test "E1 簽章正確 + success：訂單轉 paid，回 200" do
    callback!(status: "success")
    assert_response :ok
    assert_equal "applied", response.parsed_body["result"]
    assert_equal "paid", @order.reload.status
    assert_equal "paid", @payment.reload.status
  end

  test "E2 簽章正確 + failed：訂單轉 failed，釋放名額" do
    callback!(status: "failed")
    assert_equal "failed", @order.reload.status
    assert_equal 0, @reward.reload.quota_taken
  end

  test "E3 簽章錯誤：401，訂單與名額都不變" do
    callback!(status: "success", secret: "wrong-secret")
    assert_response :unauthorized
    assert_equal "pending_payment", @order.reload.status
    assert_equal 1, @reward.reload.quota_taken
    assert_equal "rejected_signature", PaymentEvent.last.result
  end

  test "E4 缺少簽章或時間戳：401" do
    body, headers = signed_callback(@payment)
    post_callback(body, headers.except("X-Signature"))
    assert_response :unauthorized
    post_callback(body, headers.except("X-Timestamp"))
    assert_response :unauthorized
  end

  test "E5 內文被竄改：401" do
    body, headers = signed_callback(@payment, amount: @payment.amount)
    tampered = body.sub(%("success"), %("failed"))
    post_callback(tampered, headers)
    assert_response :unauthorized
    assert_equal "pending_payment", @order.reload.status
  end

  test "E6 時間戳超過 5 分鐘：拒絕（防重放）" do
    callback!(timestamp: 6.minutes.ago.to_i.to_s)
    assert_response :unauthorized
    assert_equal "pending_payment", @order.reload.status
  end

  test "E7 同一個 event_id 收到兩次：第 2 次回 200 + duplicate，只轉換一次" do
    callback!(event_id: "evt_same")
    callback!(event_id: "evt_same")
    assert_response :ok
    assert_equal "duplicate", response.parsed_body["result"]
    assert_equal 1, @order.order_transitions.count
  end

  test "E9 已付款，又收到不同 event_id 的 success：忽略" do
    callback!(status: "success")
    callback!(status: "success")
    assert_equal "ignored", response.parsed_body["result"]
    assert_equal 1, @order.order_transitions.count
  end

  test "E10 先 failed 再 success：訂單維持 failed，記錄忽略原因" do
    callback!(status: "failed")
    callback!(status: "success")
    assert_equal "failed", @order.reload.status
    assert_match "忽略後到的成功通知", PaymentEvent.last.note
  end

  test "E11 先 success 再 failed：訂單維持 paid" do
    callback!(status: "success")
    callback!(status: "failed")
    assert_equal "paid", @order.reload.status
    assert_equal 1, @reward.reload.quota_taken
    assert_match "忽略失敗通知", PaymentEvent.last.note
  end

  test "E12 trade_no 不存在：200 + ignored" do
    body, headers = signed_callback(@payment)
    body = body.sub(@payment.provider_trade_no, "FK_UNKNOWN")
    headers["X-Signature"] = Payments::Signature.sign(secret: Rails.configuration.x.fake_gateway.secret,
                                                      timestamp: headers["X-Timestamp"], body: body)
    post_callback(body, headers)
    assert_response :ok
    assert_equal "ignored", response.parsed_body["result"]
  end

  test "E13 E14 金額不符：訂單維持待付款，付款標記 needs_review，訂單頁顯示異常" do
    callback!(status: "success", amount: @payment.amount + 1)
    assert_response :ok
    assert_equal "rejected_amount", response.parsed_body["result"]
    assert_equal "pending_payment", @order.reload.status
    assert_equal ["needs_review", "amount_mismatch"], @payment.reload.values_at(:status, :review_reason)

    get order_path(@order)
    assert_match "付款資訊異常，客服將與你聯繫", response.body
  end

  test "E15 訂單已過期才收到 success：訂單不變，付款標記待退款" do
    Orders::Transition.call(@order, :expire, reason: "逾期")
    callback!(status: "success")
    assert_equal "expired", @order.reload.status
    assert_equal ["needs_review", "late_payment"], @payment.reload.values_at(:status, :review_reason)
    assert_equal 0, @reward.reload.quota_taken    # 名額不會被拿回來

    get order_path(@order)
    assert_match "將為你辦理退款", response.body
  end

  test "E15 訂單已取消才收到 success：一樣標記待退款" do
    Orders::Transition.call(@order, :cancel, reason: "取消")
    callback!(status: "success")
    assert_equal "cancelled", @order.reload.status
    assert_equal "late_payment", @payment.reload.review_reason
  end

  test "E16 內文不是 JSON 或缺少欄位：400" do
    timestamp = Time.current.to_i.to_s
    secret = Rails.configuration.x.fake_gateway.secret
    ["not json", { trade_no: @payment.provider_trade_no }.to_json].each do |body|
      post_callback(body, "X-Timestamp" => timestamp,
                          "X-Signature" => Payments::Signature.sign(secret: secret, timestamp: timestamp, body: body))
      assert_response :bad_request
    end
    assert_equal "pending_payment", @order.reload.status
  end

  test "不認識的金流代號：404" do
    post payment_callback_path(provider: "unknown"), params: "{}", headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :not_found
  end
end
