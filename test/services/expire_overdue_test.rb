require "test_helper"

# F. 逾期處理
class ExpireOverdueTest < ActiveSupport::TestCase
  setup do
    @reward = create_reward(quota_total: 10)
  end

  def atm_order = place_order!(@reward, payment_method: "atm")

  test "F1 建立 ATM 訂單：付款期限預設 3 天" do
    assert_in_delta 3.days.from_now, atm_order.expires_at, 5
  end

  test "F2 還沒到期：不變" do
    order = atm_order
    Orders::ExpireOverdue.call
    assert_equal "pending_payment", order.reload.status
  end

  test "F3 已到期且仍待付款：轉 expired，釋放名額" do
    order = atm_order
    result = Orders::ExpireOverdue.call(now: 4.days.from_now)
    assert_equal 1, result.expired
    assert_equal "expired", order.reload.status
    assert_equal 0, @reward.reload.quota_taken
    assert_equal "逾期未付款", order.order_transitions.last.reason
  end

  test "F4 已付款的訂單：不受影響" do
    order = atm_order
    deliver_callback(order.latest_payment, status: "success")
    Orders::ExpireOverdue.call(now: 4.days.from_now)
    assert_equal "paid", order.reload.status
  end

  test "F5 連續執行兩次：第二次什麼都不做，名額不會被多釋放" do
    atm_order
    place_order!(@reward)   # 另一張還沒到期的信用卡訂單（15 分鐘後才到期）
    Orders::ExpireOverdue.call(now: 1.hour.from_now)
    second = Orders::ExpireOverdue.call(now: 1.hour.from_now)
    assert_equal 0, second.expired
    assert_equal 1, @reward.reload.quota_taken
  end

  test "F6 其中一筆處理失敗：跳過並記錄，其他照常處理" do
    first = atm_order
    second = atm_order
    original = Orders::Transition.method(:call)
    failing = ->(order, *args, **kw) { order.id == first.id ? raise("模擬錯誤") : original.call(order, *args, **kw) }

    stub_method(Orders::Transition, :call, failing) do
      result = Orders::ExpireOverdue.call(now: 4.days.from_now)
      assert_equal [1, 1], [result.expired, result.failed]
    end
    assert_equal "pending_payment", first.reload.status
    assert_equal "expired", second.reload.status
  end

  test "F8 信用卡 15 分鐘逾時也會過期" do
    order = place_order!(@reward)
    Orders::ExpireOverdue.call(now: 16.minutes.from_now)
    assert_equal "expired", order.reload.status
  end

  test "F9 有 needs_review 付款的訂單：跳過（錢可能已進來，不自動釋放名額）" do
    order = atm_order
    deliver_callback(order.latest_payment, amount: order.total_amount + 1)   # 金額不符
    Orders::ExpireOverdue.call(now: 4.days.from_now)
    assert_equal "pending_payment", order.reload.status
    assert_equal 1, @reward.reload.quota_taken
  end

  test "F11 已挑出要逾期的訂單後，才收到金額不符的通知：不轉 expired、不釋放名額" do
    order = atm_order
    original = Orders::Transition.method(:call)
    notify = method(:deliver_callback)   # 先存起來：替身方法執行時 self 是 Orders::Transition，叫不到測試的方法
    # 模擬時間差：逾期處理已經把訂單挑出來，在真正轉換前的那一刻，金額不符的通知到了
    callback_sneaks_in = lambda do |target, *args, **kw|
      notify.call(order.latest_payment, amount: order.total_amount + 1)
      original.call(target, *args, **kw)
    end

    result = nil
    stub_method(Orders::Transition, :call, callback_sneaks_in) do
      result = Orders::ExpireOverdue.call(now: 4.days.from_now)
    end
    assert_equal [0, 1], [result.expired, result.skipped]
    assert_equal "pending_payment", order.reload.status
    assert_equal 1, @reward.reload.quota_taken
  end

  test "F12 逾期處理用部分索引找 needs_review 付款，不掃整張 payments" do
    sql = Orders::ExpireOverdue.new(Time.current).send(:overdue_orders).to_sql
    plan = ActiveRecord::Base.connection.select_rows("EXPLAIN QUERY PLAN #{sql}").map(&:last).join("\n")
    # 「SCAN payments」後面什麼都沒接 = 整張表從頭翻到尾；
    # 「SCAN payments USING COVERING INDEX ...」是只翻那個只收 needs_review 的小索引，沒問題
    assert_no_match(/^SCAN payments$/, plan)
    assert_match(/USING COVERING INDEX index_payments_needing_review/, plan)
  end

  test "F10 ATM_EXPIRE_MINUTES 可以縮短期限（Demo 用）" do
    settings = Rails.configuration.x.checkout
    original = settings.atm_expire_minutes
    settings.atm_expire_minutes = 1
    assert_in_delta 1.minute.from_now, atm_order.expires_at, 5
  ensure
    settings.atm_expire_minutes = original
  end

  test "rake orders:expire_overdue 可以執行並印出結果" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("orders:expire_overdue")
    assert_output(/逾期處理完成/) { Rake::Task["orders:expire_overdue"].execute }
  end
end
