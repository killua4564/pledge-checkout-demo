# 所有金流 adapter 的共同介面。
#
# 就像統一規格的插座：今天插「假金流」，明天換「綠界」，訂單與狀態機都不用改。
# 新的金流只要繼承這個類別，實作下面這幾個方法。
module Payments
  module Adapters
    class Base
      # 付款方式代號，例如 "credit_card"
      def method_key = raise(NotImplementedError)

      # 結帳頁顯示的名稱與說明
      def label = raise(NotImplementedError)
      def description = nil

      # 金流商代號，callback 網址 /payments/callbacks/:provider 用
      def provider = raise(NotImplementedError)

      # 是否開放使用
      def available? = true

      # 向金流建立付款，回傳 Payments::PaymentStart（付款紀錄 + 下一步網址）
      def create_payment(order) = raise(NotImplementedError)

      # 驗證並解析 callback，回傳 Payments::CallbackEvent
      # 簽章不對丟 SignatureError，格式不對丟 MalformedPayload
      def parse_callback(raw_body:, headers:) = raise(NotImplementedError)

      # 退款：擴充點，目前不實作
      def refund(payment)
        raise NotImplementedError, "#{self.class.name} 尚未支援退款"
      end

      # 把 decimal 金額轉成這家金流要的格式。
      # 預設：依幣別小數位數轉成字串（TWD 2980.00 → "2980"、USD 19.9 → "19.90"）。
      # 像 Stripe 要整數「分」的金流，就在自己的 adapter 覆寫成 (amount * 100).to_i
      def gateway_amount(amount, currency)
        format("%.#{Money.precision(currency)}f", Money.round(amount, currency))
      end
    end
  end
end
