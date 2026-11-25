# 把逾期未付款的訂單轉為 expired，並釋放名額。
#
# 條件：待付款 + 已超過付款期限 + 沒有「需要人工處理」的付款
#   （有 needs_review 的訂單，錢可能已經進來了，交給人工處理，不自動釋放名額）
#
# 執行方式：bin/rails orders:expire_overdue（部署在 Heroku 時可用 Scheduler 定期執行）
module Orders
  class ExpireOverdue
    Result = Data.define(:expired, :skipped, :failed)

    def self.call(now: Time.current) = new(now).call

    def initialize(now)
      @now = now
    end

    def call
      expired = skipped = failed = 0

      overdue_orders.find_each do |order|
        Orders::Transition.call(order, :expire, reason: "逾期未付款")
        expired += 1
      rescue Order::InvalidTransition
        skipped += 1    # 剛好在這一刻被付款或取消了，不用處理
      rescue StandardError => e
        failed += 1     # 單筆出錯不影響其他訂單
        Rails.logger.error("[逾期處理] 訂單 #{order.public_id} 失敗：#{e.class} #{e.message}")
      end

      Result.new(expired:, skipped:, failed:)
    end

    private

    def overdue_orders
      Order.where(status: "pending_payment")
           .where(expires_at: ...@now)
           .where.not(id: Payment.where(status: "needs_review").select(:order_id))
    end
  end
end
