# 假金流頁面的共用設定。這些頁面扮演「金流公司的網站」，只在開發與測試環境存在。
module FakeGateway
  class BaseController < ApplicationController
    layout "fake_gateway"

    private

    def find_payment
      @payment = Payment.includes(:order).find_by!(provider: "fake", provider_trade_no: params[:trade_no])
      @order = @payment.order
    end

    # 在背景送出 callback；delay 秒後才送，模擬「金流通知比瀏覽器晚到」。
    # event_id 在這裡就決定好：送失敗重試時沿用同一個編號，和真實金流重送通知的行為一樣
    def enqueue_callback(status, delay: 0)
      job = delay.positive? ? DeliverFakeCallbackJob.set(wait: delay.seconds) : DeliverFakeCallbackJob
      job.perform_later(@payment.id, status, event_id: "evt_#{SecureRandom.hex(8)}")
    end
  end
end
