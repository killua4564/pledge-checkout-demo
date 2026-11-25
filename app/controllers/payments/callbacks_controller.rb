# POST /payments/callbacks/:provider：接收金流的付款結果通知。
#
# 這是給「金流的伺服器」呼叫的，不是給瀏覽器的，所以不檢查 CSRF token。
# 取而代之的是驗證簽章（在 Payments::ProcessCallback 裡）。
module Payments
  class CallbacksController < ApplicationController
    skip_forgery_protection

    def create
      result = Payments::ProcessCallback.call(
        # 用網址上的參數，不用 params：params 會試著解析 JSON 內文，內文壞掉時在這裡就出錯，
        # 我們要讓「內文格式不對」由處理流程統一判斷並回 400
        provider: request.path_parameters[:provider],
        raw_body: request.raw_post,
        headers: { "X-Timestamp" => request.headers["X-Timestamp"], "X-Signature" => request.headers["X-Signature"] }
      )
      render json: { ok: result.http_status == :ok, result: result.result, note: result.note }, status: result.http_status
    end
  end
end
