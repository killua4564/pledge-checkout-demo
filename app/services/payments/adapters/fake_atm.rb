# 假 ATM 金流：建立付款時產生虛擬帳號與繳費期限，使用者看到後再去「轉帳」。
module Payments
  module Adapters
    class FakeAtm < FakeBase
      def method_key = "atm"
      def label = "ATM 轉帳或銀行臨櫃繳款"
      def description = "需於指定時間內完成付款，超過時間將取消交易"

      def create_payment(order)
        payment = create_payment_record(
          order,
          virtual_account: "9#{SecureRandom.random_number(10**13).to_s.rjust(13, '0')}",  # 14 碼虛擬帳號
          pay_deadline: order.expires_at
        )
        PaymentStart.new(payment: payment, next_path: routes.order_path(order))
      end
    end
  end
end
