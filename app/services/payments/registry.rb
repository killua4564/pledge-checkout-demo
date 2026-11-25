# 付款方式 → adapter 的對照表。
#
# 想換成真實金流（例如綠界），只要寫一個新的 adapter 類別，然後在這裡改一行。
# 訂單、狀態機、callback 處理流程都不用動。
module Payments
  class Registry
    # 順序就是結帳頁顯示的順序（信用卡、AFTEE、ATM）
    DEFAULTS = {
      "credit_card" => "Payments::Adapters::FakeCreditCard",
      "aftee"       => "Payments::Adapters::Aftee",
      "atm"         => "Payments::Adapters::FakeAtm",
    }.freeze

    class << self
      # 依付款方式取得 adapter
      def fetch(method)
        name = adapters.fetch(method.to_s) { raise NotAvailable, "不支援的付款方式：#{method}" }
        name.constantize.new
      end

      def known?(method) = adapters.key?(method.to_s)

      def available?(method) = known?(method) && fetch(method).available?

      # 結帳頁列出所有付款方式（包含尚未開放的）
      def all = adapters.keys.map { |method| fetch(method) }

      # 依金流商代號找 adapter（callback 網址 /payments/callbacks/:provider 用）
      def for_provider(provider)
        all.find { |adapter| adapter.provider == provider.to_s && adapter.available? }
      end

      # 註冊新的 adapter（測試用，也示範「新增金流不用改其他程式」）
      def register(method, class_name)
        @adapters = adapters.merge(method.to_s => class_name.to_s)
      end

      def reset! = @adapters = nil

      private

      def adapters = @adapters ||= DEFAULTS.dup
    end
  end
end
