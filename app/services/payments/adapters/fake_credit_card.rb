# 假信用卡金流：建立付款後，把使用者導到假金流的付款頁，由使用者選擇成功或失敗。
module Payments
  module Adapters
    class FakeCreditCard < FakeBase
      def method_key = "credit_card"
      def label = "信用卡付款"
      def description = "台新、玉山享 3 期零利率，可用國外卡"

      def create_payment(order)
        payment = create_payment_record(order)
        PaymentStart.new(payment: payment, next_path: routes.fake_gateway_pay_path(payment.provider_trade_no))
      end
    end
  end
end
