# AFTEE（先享後付）：顯示在結帳頁，但尚未開放。
# 之後要接上，只要實作 create_payment 與 parse_callback，並把 available? 改成 true。
module Payments
  module Adapters
    class Aftee < Base
      def method_key = "aftee"
      def label = "AFTEE"
      def description = "安心便利，免註冊免綁卡（尚未開放）"
      def provider = "aftee"
      def available? = false

      def create_payment(_order)
        raise NotAvailable, "AFTEE 尚未開放"
      end
    end
  end
end
