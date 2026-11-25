# POST /checkout/quote：結帳頁的「即時金額預覽」。
# 前端（Stimulus）把目前表單的選擇送過來，伺服器算好金額，回傳要替換的 HTML 片段。
# 前端完全不做金額計算。
class QuotesController < ApplicationController
  def create
    reward = Reward.find(params.dig(:checkout, :reward_id))
    checkout = params.fetch(:checkout, {})
    @quote = Checkout::PriceCalculator.call(
      reward: reward,
      addon_ids: checkout[:addon_ids],
      discount_code: checkout[:discount_code],
      region: checkout[:ship_region],
      donation: checkout[:donation]
    )

    # 一次更新兩個地方：左側金額明細、送出按鈕上的金額
    render turbo_stream: [
      turbo_stream.replace("price_summary", partial: "checkouts/price_summary", locals: { quote: @quote }),
      turbo_stream.replace("pay_amount", partial: "checkouts/pay_amount", locals: { quote: @quote })
    ]
  end
end
