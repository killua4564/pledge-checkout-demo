# 首頁：列出專案，並可輸入方案 ID 直接前往結帳。
class HomeController < ApplicationController
  include PublicCacheable

  ERROR_MESSAGES = {
    "not_found" => "找不到這個方案 ID，請確認後再試一次",
    "blank"     => "請輸入方案 ID",
  }.freeze

  def index
    allow_public_cache!
    @projects = Project.includes(:rewards).order(:id)
    # 錯誤訊息用網址參數帶，不用 flash：flash 需要 session cookie，會讓首頁無法被快取
    @error = ERROR_MESSAGES[params[:error]]
  end

  # GET /go?reward_id=1 → 轉到該方案的結帳頁
  def go
    input = params[:reward_id].to_s.strip
    return redirect_to(root_path(error: "blank")) if input.empty?

    reward = input.match?(/\A\d+\z/) && Reward.includes(:project).find_by(id: input)
    return redirect_to(root_path(error: "not_found")) unless reward

    redirect_to project_checkout_path(reward.project, reward: reward.id)
  end
end
