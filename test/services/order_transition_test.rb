require "test_helper"

# B. 訂單狀態轉換（單執行緒的部分；並行的 B5、B6 在 concurrency_test.rb）
class OrderTransitionTest < ActiveSupport::TestCase
  setup do
    @reward = create_reward(quota_total: 10)
    @order = place_order!(@reward)
  end

  test "B1 待付款可以轉為 paid / failed / cancelled / expired，並留下紀錄與時間" do
    { pay: "paid", fail: "failed", cancel: "cancelled", expire: "expired" }.each do |event, status|
      order = place_order!(@reward)
      Orders::Transition.call(order, event, reason: "測試")
      assert_equal status, order.status
      assert order.public_send(:"#{status}_at"), "#{status}_at 應該有時間"
      assert_equal [["pending_payment", status]], order.order_transitions.pluck(:from_status, :to_status)
    end
  end

  test "B2 已付款的訂單不能再轉成任何狀態，資料不變" do
    Orders::Transition.call(@order, :pay, reason: "付款")
    %i[pay fail cancel expire].each do |event|
      assert_raises(Order::InvalidTransition) { Orders::Transition.call(@order, event, reason: "非法") }
    end
    assert_equal "paid", @order.reload.status
    assert_equal 1, @order.order_transitions.count
  end

  test "B3 failed / cancelled / expired 都是終點" do
    { fail: "failed", cancel: "cancelled", expire: "expired" }.each_key do |event|
      order = place_order!(@reward)
      Orders::Transition.call(order, event, reason: "測試")
      assert_raises(Order::InvalidTransition) { Orders::Transition.call(order, :pay, reason: "非法") }
    end
  end

  test "B4 不存在的事件名稱：拒絕" do
    assert_raises(Order::InvalidTransition) { Orders::Transition.call(@order, :refund, reason: "不存在") }
  end

  test "B7 轉為 failed / cancelled / expired 會釋放名額；轉為 paid 不會" do
    assert_equal 1, @reward.reload.quota_taken
    Orders::Transition.call(@order, :fail, reason: "失敗")
    assert_equal 0, @reward.reload.quota_taken

    paid = place_order!(@reward)
    Orders::Transition.call(paid, :pay, reason: "付款")
    assert_equal 1, @reward.reload.quota_taken
  end

  test "B8 轉換中途出錯：整個交易回復，狀態與名額都不變" do
    stub_method(OrderTransition, :create!, ->(*, **) { raise "模擬寫入失敗" }) do
      assert_raises(RuntimeError) { Orders::Transition.call(@order, :fail, reason: "失敗") }
    end
    assert_equal "pending_payment", @order.reload.status
    assert_equal 1, @reward.reload.quota_taken
  end
end
