# 付款相關的共用錯誤類別與資料結構。
module Payments
  class Error < StandardError; end
  class NotAvailable < Error; end        # 付款方式尚未開放（例如 AFTEE）
  class SignatureError < Error; end      # callback 簽章錯誤、缺少或過期
  class MalformedPayload < Error; end    # callback 內容格式不對

  # 建立付款後的結果：付款紀錄 + 使用者下一步要去的網址
  PaymentStart = Data.define(:payment, :next_path)

  # 各家金流的 callback 解析後，統一轉成這個格式，後面的處理流程就不用管是哪一家金流
  CallbackEvent = Data.define(:event_id, :trade_no, :status, :amount, :currency) do
    def success? = status == "success"
  end
end
