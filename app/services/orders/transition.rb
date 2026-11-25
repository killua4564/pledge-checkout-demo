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
module Orders
  class Transition
    def self.call(order, event, reason:)
      new(order, event, reason).call
    end

    def initialize(order, event, reason)
      @order = order
      @event = event
      @reason = reason
    end

    def call
      rule = Order::TRANSITIONS.fetch(@event) do
        raise Order::InvalidTransition, "不存在的事件：#{@event}"
      end
      now = Time.current

      Order.transaction do
        changed = Order.where(id: @order.id, status: rule[:from])
                       .update_all(status: rule[:to], "#{rule[:to]}_at": now, updated_at: now)

        # 影響 0 列：訂單目前不是 rule[:from]（可能早就被別人處理了），拒絕這次轉換
        if changed.zero?
          current = Order.where(id: @order.id).pick(:status)
          raise Order::InvalidTransition, "無法從「#{current}」執行 #{@event}"
        end

        Inventory.release(@order.reward_id) if Order::RELEASING_STATUSES.include?(rule[:to])

        OrderTransition.create!(order_id: @order.id, from_status: rule[:from], to_status: rule[:to], reason: @reason)
      end

      @order.reload
    end
  end
end
