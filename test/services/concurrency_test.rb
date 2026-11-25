require "test_helper"

# D. 名額不超賣，以及 B5、B6、E8、F7 這些「同時發生」的情況。
#
# 這些測試真的開多條執行緒同時打資料庫，所以不能用 Rails 預設的「每個測試包在交易裡、結束後回復」
# （那樣所有執行緒會共用同一個交易，測不出搶資源的情況）。改成每個測試結束後手動清空資料表。
class ConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  teardown do
    [PaymentEvent, Payment, OrderTransition, OrderDiscount, OrderAddon, Order,
     DiscountCode, ShippingRate, Addon, Reward, Project].each(&:delete_all)
  end

  # 讓 n 條執行緒「盡量同一瞬間」開始執行同一段程式，回傳每條執行緒的結果
  def run_concurrently(n)
    ready = Queue.new
    go = Queue.new
    threads = n.times.map do |i|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          go.pop                      # 等發令槍
          yield i
        end
      end
    end
    n.times { ready.pop }             # 等大家都就位
    n.times { go << true }            # 發令
    threads.map(&:value)
  end

  def try_order(reward)
    Orders::Create.call(reward: Reward.find(reward.id), params: checkout_params(reward)).success?
  end

  test "D1 剩 1 個名額，兩人先後下單：第 2 人被拒絕" do
    reward = create_reward(quota_total: 1)
    assert try_order(reward)
    refute try_order(reward)
  end

  test "D2 剩 1 個名額，兩條執行緒同時下單：只有 1 張成功" do
    reward = create_reward(quota_total: 1)
    results = run_concurrently(2) { try_order(reward) }
    assert_equal 1, results.count(true)
    assert_equal 1, reward.reload.quota_taken
    assert_equal 1, Order.count
  end

  test "D3 剩 5 個名額，10 條執行緒同時下單：只有 5 張成功" do
    reward = create_reward(quota_total: 5)
    results = run_concurrently(10) { try_order(reward) }
    assert_equal 5, results.count(true)
    assert_equal 5, reward.reload.quota_taken
  end

  test "D4 付款失敗、逾期、取消後名額釋放，其他人可以再買" do
    reward = create_reward(quota_total: 1)
    %i[fail expire cancel].each do |event|
      order = place_order!(reward)
      refute try_order(reward), "名額滿時應該買不到"
      Orders::Transition.call(order, event, reason: "測試")
    end
    assert try_order(reward)
  end

  test "D5 直接把 quota_taken 寫成超過上限：被資料庫 CHECK 約束拒絕" do
    reward = create_reward(quota_total: 1)
    assert_raises(ActiveRecord::StatementInvalid) { reward.update_column(:quota_taken, 2) }
    assert_raises(ActiveRecord::StatementInvalid) { reward.update_column(:quota_taken, -1) }
  end

  test "D6 扣名額後建立訂單失敗：交易回復，名額沒有被佔走" do
    reward = create_reward(quota_total: 1)
    stub_method(Order, :create!, ->(*, **) { raise ActiveRecord::RecordInvalid }) do
      assert_raises(ActiveRecord::RecordInvalid) do
        Orders::Create.call(reward: reward, params: checkout_params(reward))
      end
    end
    assert_equal 0, reward.reload.quota_taken
  end

  test "D7 已付款的訂單不釋放名額" do
    reward = create_reward(quota_total: 1)
    order = place_order!(reward)
    deliver_callback(order.latest_payment, status: "success")
    Orders::ExpireOverdue.call(now: 1.day.from_now)
    assert_equal 1, reward.reload.quota_taken
  end

  test "B5 兩條執行緒同時對同一張訂單 pay：只有一次成功" do
    order = place_order!(create_reward)
    results = run_concurrently(2) do
      Orders::Transition.call(Order.find(order.id), :pay, reason: "並行")
      :ok
    rescue Order::InvalidTransition
      :rejected
    end
    assert_equal [:ok, :rejected], results.sort
    assert_equal 1, OrderTransition.where(order_id: order.id).count
  end

  test "B6 同時呼叫 expire 與 cancel：只有一個成功，名額只釋放一次" do
    reward = create_reward(quota_total: 5)
    order = place_order!(reward)
    place_order!(reward)                      # 另一張訂單也佔一個名額
    results = run_concurrently(2) do |i|
      Orders::Transition.call(Order.find(order.id), i.zero? ? :expire : :cancel, reason: "並行")
      :ok
    rescue Order::InvalidTransition
      :rejected
    end
    assert_equal [:ok, :rejected], results.sort
    assert_equal 1, reward.reload.quota_taken
  end

  test "E8 同一個 event_id 由兩條執行緒同時送達：只有一個 applied" do
    order = place_order!(create_reward)
    body, headers = signed_callback(order.latest_payment, event_id: "evt_race")
    results = run_concurrently(2) do
      Payments::ProcessCallback.call(provider: "fake", raw_body: body, headers: headers).result
    end
    assert_equal %w[applied duplicate], results.sort
    assert_equal 1, OrderTransition.where(order_id: order.id).count
  end

  test "F7 逾期處理與付款通知同時發生：結果只會是 paid，或 expired + 待退款" do
    reward = create_reward(quota_total: 5)
    order = place_order!(reward, payment_method: "atm")
    payment = order.latest_payment
    run_concurrently(2) do |i|
      if i.zero?
        Orders::ExpireOverdue.call(now: 4.days.from_now)
      else
        deliver_callback(payment, status: "success")
      end
    end

    order.reload
    payment.reload
    case order.status
    when "paid"
      assert_equal "paid", payment.status
      assert_equal 1, reward.reload.quota_taken
    when "expired"
      assert_equal "late_payment", payment.review_reason
      assert_equal 0, reward.reload.quota_taken
    else
      flunk "非預期的狀態：#{order.status}"
    end
  end
end
