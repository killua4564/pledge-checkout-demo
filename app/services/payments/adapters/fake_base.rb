# 假金流（信用卡與 ATM 共用的部分）。
# 對應的假金流頁面在 app/controllers/fake_gateway/，送 callback 的程式在 Payments::FakeGatewayNotifier。
module Payments
  module Adapters
    class FakeBase < Base
      def provider = "fake"

      # 驗證簽章，再把 JSON 內文轉成統一的 CallbackEvent
      def parse_callback(raw_body:, headers:)
        Payments::Signature.verify!(
          secret: Rails.configuration.x.fake_gateway.secret,
          timestamp: headers["X-Timestamp"],
          signature: headers["X-Signature"],
          body: raw_body
        )

        data = JSON.parse(raw_body)
        required = %w[event_id trade_no status amount currency]
        missing = required.reject { |key| data[key].present? }
        raise MalformedPayload, "缺少欄位：#{missing.join(', ')}" if missing.any?
        raise MalformedPayload, "status 只能是 success 或 failed" unless %w[success failed].include?(data["status"])

        CallbackEvent.new(
          event_id: data["event_id"],
          trade_no: data["trade_no"],
          status: data["status"],
          amount: BigDecimal(data["amount"].to_s),
          currency: data["currency"]
        )
      rescue JSON::ParserError, ArgumentError, TypeError
        raise MalformedPayload, "內文不是正確的 JSON"
      end

      private

      def new_trade_no = "FK#{Time.current.strftime('%Y%m%d')}#{SecureRandom.alphanumeric(8).upcase}"

      def create_payment_record(order, **extra)
        order.payments.create!(
          payment_method: method_key,
          provider: provider,
          provider_trade_no: new_trade_no,
          amount: order.total_amount,
          currency: order.currency,
          **extra
        )
      end

      def routes = Rails.application.routes.url_helpers
    end
  end
end
