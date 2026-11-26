# 執行訂單狀態轉換。callback、逾期處理、使用者取消、0 元訂單都呼叫這一個地方。
#
# 用法：Orders::Transition.call(order, :pay, reason: "金流通知付款成功")
#
# 在同一個資料庫交易內做三件事：
#   1. 條件更新狀態：UPDATE orders SET status = 'paid' WHERE id = ? AND status = 'pending_payment'
#      → 「檢查目前狀態」和「改狀態」是同一句 SQL，兩個 callback 同時到也只有一個會成功
#   2. 如果轉到失效狀態（failed / cancelled / expired），把名額還回去
#   3. 寫一筆 order_transitions 稽核紀錄
#
# 因為第 1 步保證一張訂單只會離開 pending_payment 一次，名額也只會被釋放一次。
#
# guard（選填）：呼叫端想再加的條件（一個 Order 的查詢範圍），會併進第 1 步的同一句 UPDATE。
#   例：逾期處理附加「沒有需人工處理的付款」，條件不成立就和狀態不對一樣，丟 InvalidTransition。
#   重點是「檢查」和「動作」在同一句 SQL 裡完成，不要先查再改（spec §4.3）。
module Orders
  class Transition
    def self.call(order, event, reason:, guard: nil)
      new(order, event, reason, guard).call
    end

    def initialize(order, event, reason, guard = nil)
      @order = order
      @event = event
      @reason = reason
      @guard = guard
    end

    def call
      rule = Order::TRANSITIONS.fetch(@event) do
        raise Order::InvalidTransition, "不存在的事件：#{@event}"
      end
      now = Time.current

      Order.transaction do
        scope = Order.where(id: @order.id, status: rule[:from])
        # 用 and 不用 merge：merge 遇到同一個欄位（例如兩邊都對 id 下條件）會用後者「覆蓋」前者，
        # 「id = 這張訂單」會被蓋掉，變成一次更新一整批訂單。and 會保留兩邊的條件。
        scope = scope.and(@guard) if @guard
        changed = scope.update_all(status: rule[:to], "#{rule[:to]}_at": now, updated_at: now)

        # 影響 0 列：訂單目前不是 rule[:from]（可能早就被別人處理了），或 guard 條件不成立，拒絕這次轉換
        if changed.zero?
          current = Order.where(id: @order.id).pick(:status)
          reason = current == rule[:from] && @guard ? "（附加條件不成立）" : ""
          raise Order::InvalidTransition, "無法從「#{current}」執行 #{@event}#{reason}"
        end

        Inventory.release(@order.reward_id) if Order::RELEASING_STATUSES.include?(rule[:to])

        OrderTransition.create!(order_id: @order.id, from_status: rule[:from], to_status: rule[:to], reason: @reason)
      end

      @order.reload
    end
  end
end
