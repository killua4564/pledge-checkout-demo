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
        # 「沒有需人工處理的付款」這個條件，在轉換的那句 UPDATE 裡再寫一次（guard）。
        # 因為從「挑出名單」到「真正轉換」之間有時間差，這段時間可能剛好收到金額不符的通知；
        # 把檢查和動作放在同一句 SQL，就沒有空檔可以插隊（spec §6.7）。
        Orders::Transition.call(order, :expire, reason: "逾期未付款", guard: without_review)
        expired += 1
      rescue Order::InvalidTransition
        skipped += 1    # 剛好在這一刻被付款、取消，或付款被標為需人工處理，不用處理
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
           .and(without_review)   # 用 and 保留兩邊條件（merge 遇到同欄位會覆蓋，見 Transition）
    end

    # 「沒有需人工處理的付款」的訂單。挑名單和轉換時共用同一個條件，確保兩邊規則一致。
    # 子查詢會用到 payments 的部分索引 index_payments_needing_review（spec §3.9）。
    def without_review
      Order.where.not(id: Payment.where(status: "needs_review").select(:order_id))
    end
  end
end
