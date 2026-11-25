# 在背景送出假金流的 callback。
# 放在背景是為了模擬真實情況：金流的通知是「非同步」的，可能比使用者的瀏覽器晚到。
class DeliverFakeCallbackJob < ApplicationJob
  queue_as :default

  # 送不出去（例如伺服器忙）就稍後重試，最多 3 次
  retry_on StandardError, wait: 2.seconds, attempts: 3

  def perform(payment_id, status, event_id: nil, amount: nil, bad_signature: false)
    payment = Payment.find(payment_id)
    Payments::FakeGatewayNotifier.deliver(payment, status:, event_id:, amount: amount && BigDecimal(amount), bad_signature:)
  end
end
