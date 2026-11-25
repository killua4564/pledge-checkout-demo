# 結帳頁 /projects/:slug/checkout?reward=<方案 ID>
#
# 這是「寫入」頁面：裡面有表單和 CSRF token，每個人都不一樣，所以不可快取
# （ApplicationController 預設就回 Cache-Control: no-store）。
class CheckoutsController < ApplicationController
  def show
    @project = Project.find_by!(slug: params[:project_slug])
    # 沒帶方案 → 先回選方案頁
    return redirect_to(project_rewards_path(@project)) if params[:reward].blank?

    # 方案必須屬於這個專案，否則 404
    @reward = @project.rewards.includes(:shipping_rates).find(params[:reward])
    # 每次進入結帳頁都產生新的 checkout_token，代表「這一次結帳」，用來防止重複送出
    @form = CheckoutForm.new(reward_id: @reward.id, checkout_token: SecureRandom.uuid)
    @quote = Checkout::PriceCalculator.call(reward: @reward)
  end
end
