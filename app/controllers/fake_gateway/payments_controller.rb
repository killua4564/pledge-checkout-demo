# 假金流的信用卡付款頁：使用者選「付款成功」或「付款失敗」。
#
# 按下後做兩件事（模擬真實金流）：
#   1. 立刻把瀏覽器導回我們的訂單頁（這時訂單頁顯示「付款處理中」）
#   2. 在背景另外送 callback 給我們的系統（這才是真正會改變訂單狀態的通知）
module FakeGateway
  class PaymentsController < BaseController
    before_action :find_payment

    def show; end

    def decide
      status = params[:result] == "success" ? "success" : "failed"
      enqueue_callback(status, delay: params[:delay].to_i.clamp(0, 30))
      redirect_to order_path(@order), status: :see_other
    end
  end
end
