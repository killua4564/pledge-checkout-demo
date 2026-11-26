# 處理金流送來的 callback（付款結果通知）。對照 docs/spec.md §6.5。
#
# 只有「簽章正確」的 callback 能改變訂單狀態；使用者的瀏覽器導回來不算數。
#
# 處理順序：
#   1. 驗證簽章（錯 → 401，不動任何資料）
#   2. 用 trade_no 找到付款（找不到 → 200 + ignored）
#   3. 寫入 payment_events。同一個 event_id 第二次寫入會撞到唯一索引 → 200 + duplicate（冪等）
#   4. 金額不符 → 付款標記 needs_review
#   5. 依訂單目前狀態決定怎麼做（見 #apply_success / #apply_failure）
#
# 為什麼重複通知、找不到交易也回 200？
#   金流看到非 200 會一直重送。回 200 只代表「收到了」，不代表我們接受這筆付款。
module Payments
  class ProcessCallback
    Result = Data.define(:http_status, :result, :note)

    def self.call(provider:, raw_body:, headers:) = new(provider:, raw_body:, headers:).call

    def initialize(provider:, raw_body:, headers:)
      @provider = provider.to_s
      @raw_body = raw_body.to_s
      @headers = headers
    end

    def call
      adapter = Registry.for_provider(@provider)
      return Result.new(http_status: :not_found, result: "ignored", note: "不認識的金流：#{@provider}") unless adapter

      event = adapter.parse_callback(raw_body: @raw_body, headers: @headers)
      payment = Payment.find_by(provider: @provider, provider_trade_no: event.trade_no)

      unless payment
        record(event_id: event.event_id, result: "ignored", note: "找不到交易 #{event.trade_no}")
        return Result.new(http_status: :ok, result: "ignored", note: "找不到交易")
      end

      process(event, payment)
    rescue SignatureError => e
      record(signature_valid: false, result: "rejected_signature", note: e.message)
      Result.new(http_status: :unauthorized, result: "rejected_signature", note: e.message)
    rescue MalformedPayload => e
      record(result: "malformed", note: e.message)
      Result.new(http_status: :bad_request, result: "malformed", note: e.message)
    rescue ActiveRecord::RecordNotUnique
      # 同一個 event_id 已經處理過：不再處理，只留紀錄（event_id 留空，避免再次撞到唯一索引）
      record(payment: payment, result: "duplicate", note: "重複通知 #{event&.event_id}")
      Result.new(http_status: :ok, result: "duplicate", note: "重複通知，已忽略")
    end

    private

    # 寫入事件紀錄 + 改狀態，放在同一個交易：中途出錯就全部回復，金流重送時可以重新處理
    def process(event, payment)
      ApplicationRecord.transaction do
        log = PaymentEvent.create!(provider: @provider, event_id: event.event_id, payment: payment,
                                   signature_valid: true, raw_body: @raw_body, result: "ignored")
        result, note = apply(event, payment)
        log.update!(result: result, note: note)
        Result.new(http_status: :ok, result: result, note: note)
      end
    end

    def apply(event, payment)
      if event.amount != payment.amount || event.currency != payment.currency
        note = "金額不符：通知 #{event.amount} #{event.currency}，應為 #{payment.amount} #{payment.currency}"
        # 付款已經 paid 時 flag_for_review! 不會改狀態（回傳 false），只把這則通知記下來
        flagged = payment.flag_for_review!("amount_mismatch")
        return ["rejected_amount", flagged ? note : "#{note}；付款已完成，只記錄不改狀態"]
      end

      event.success? ? apply_success(payment) : apply_failure(payment)
    end

    def apply_success(payment)
      Orders::Transition.call(payment.order, :pay, reason: "金流通知付款成功（#{payment.provider_trade_no}）")
      payment.update!(status: "paid")
      ["applied", "訂單已付款"]
    rescue Order::InvalidTransition
      # 訂單已經不是待付款：看目前狀態決定
      order = payment.order.reload
      case order.status
      when "paid"
        ["ignored", "訂單已是已付款，忽略"]
      when "failed"
        ["ignored", "訂單已失敗，忽略後到的成功通知"]
      else # expired / cancelled：錢進來了但訂單已失效 → 標記待退款
        payment.flag_for_review!("late_payment")
        ["ignored", "訂單已#{order.status_label}才收到付款，標記待人工退款"]
      end
    end

    def apply_failure(payment)
      Orders::Transition.call(payment.order, :fail, reason: "金流通知付款失敗（#{payment.provider_trade_no}）")
      payment.update!(status: "failed")
      ["applied", "訂單付款失敗，已釋放名額"]
    rescue Order::InvalidTransition
      ["ignored", "訂單已是「#{payment.order.reload.status_label}」，忽略失敗通知"]
    end

    def record(result:, note:, event_id: nil, payment: nil, signature_valid: true)
      PaymentEvent.create!(provider: @provider, event_id: event_id, payment: payment,
                           signature_valid: signature_valid, raw_body: @raw_body, result: result, note: note)
    end
  end
end
