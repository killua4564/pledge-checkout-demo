# 扮演「假金流」送 callback 給我們的系統。
#
# 真實世界裡這段程式在金流公司那邊；這裡為了 Demo 自己寫一個。
# 它會：組出通知內容 → 用共享密鑰簽章 → 用 HTTP POST 送到 /payments/callbacks/fake
#
# 除錯用的參數可以故意製造異常情況（Demo「簽章錯誤」「金額不符」「重複通知」）：
#   event_id:      指定事件編號（重送同一個編號 = 重複通知）
#   amount:        指定金額（和訂單不同 = 金額不符）
#   bad_signature: 用錯誤的密鑰簽章
require "net/http"

module Payments
  class FakeGatewayNotifier
    def self.deliver(payment, status:, event_id: nil, amount: nil, bad_signature: false)
      new(payment).deliver(status:, event_id:, amount:, bad_signature:)
    end

    def initialize(payment)
      @payment = payment
    end

    def deliver(status:, event_id: nil, amount: nil, bad_signature: false)
      adapter = Registry.fetch(@payment.payment_method)
      body = {
        event_id: event_id || "evt_#{SecureRandom.hex(8)}",
        trade_no: @payment.provider_trade_no,
        status: status,
        amount: adapter.gateway_amount(amount || @payment.amount, @payment.currency),
        currency: @payment.currency,
        sent_at: Time.current.iso8601
      }.to_json

      timestamp = Time.current.to_i.to_s
      secret = bad_signature ? "wrong-secret" : Rails.configuration.x.fake_gateway.secret
      headers = {
        "Content-Type" => "application/json",
        "X-Timestamp" => timestamp,
        "X-Signature" => Signature.sign(secret:, timestamp:, body:)
      }

      # 記住最後一次送出的內容，Demo 頁的「重送」按鈕會用到
      @payment.update!(payload: @payment.payload.merge("last_callback" => { "status" => status, "event_id" => JSON.parse(body)["event_id"] }))

      send_request(body, headers)
    end

    private

    def send_request(body, headers)
      case Rails.configuration.x.fake_gateway.delivery
      when :inline
        # 測試環境：直接呼叫處理流程
        ProcessCallback.call(provider: "fake", raw_body: body, headers: headers)
      else
        # 開發環境：真的發 HTTP 請求給自己的伺服器，和真實金流一樣
        uri = URI.join(Rails.configuration.x.fake_gateway.callback_base_url, "/payments/callbacks/fake")
        response = Net::HTTP.post(uri, body, headers)
        # HTTP 回應內容預設是「未知編碼」，裡面有中文時要先標成 UTF-8 才能和中文記錄文字接在一起
        Rails.logger.info("[假金流] callback #{uri} → HTTP #{response.code} #{response.body.to_s.dup.force_encoding('UTF-8')}")
        response
      end
    end
  end
end
