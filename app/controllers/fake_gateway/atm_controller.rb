# 假金流的 ATM 模擬頁：按「模擬已轉帳」就當作使用者去 ATM 轉帳了，金流隨後送出付款成功通知。
module FakeGateway
  class AtmController < BaseController
    before_action :find_payment

    def show; end

    def transfer
      enqueue_callback("success")
      redirect_to order_path(@order), status: :see_other
    end
  end
end
