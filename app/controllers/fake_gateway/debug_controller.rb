# Demo 工具頁：故意製造各種異常情況，展示系統怎麼應對。
#   重送最後一次通知（同一個 event_id）→ 冪等：不會重複處理
#   錯誤簽章 → 401，訂單不變
#   金額不符 → 付款標記為需要人工處理
#   先成功再失敗 → 訂單維持已付款
#   執行逾期處理 → 等同 bin/rails orders:expire_overdue
module FakeGateway
  class DebugController < BaseController
    SCENARIOS = %w[resend bad_signature amount_mismatch success_then_failed success failed].freeze

    def index
      @payments = Payment.includes(order: :reward).order(id: :desc).limit(15)
      @events = PaymentEvent.order(id: :desc).limit(20)
    end

    def create
      payment = Payment.find(params[:payment_id])
      scenario = params[:scenario]
      raise ActiveRecord::RecordNotFound unless SCENARIOS.include?(scenario)

      # 這裡同步送出（不放背景），按完回到頁面就能看到結果
      notifier = ->(**opts) { Payments::FakeGatewayNotifier.deliver(payment.reload, **opts) }
      case scenario
      when "resend"
        last = payment.payload["last_callback"]
        return redirect_to(fake_gateway_debug_path, alert: "這筆付款還沒送過通知") unless last
        notifier.call(status: last["status"], event_id: last["event_id"])
      when "bad_signature"   then notifier.call(status: "success", bad_signature: true)
      when "amount_mismatch" then notifier.call(status: "success", amount: payment.amount + 1)
      when "success_then_failed"
        notifier.call(status: "success")
        notifier.call(status: "failed")
      else notifier.call(status: scenario)
      end

      redirect_to fake_gateway_debug_path, notice: "已送出：#{scenario}"
    end

    def expire_overdue
      result = Orders::ExpireOverdue.call
      redirect_to fake_gateway_debug_path, notice: "逾期處理：轉為已過期 #{result.expired} 筆"
    end
  end
end
