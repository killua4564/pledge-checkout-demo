# 剩餘名額（讀取）。
# 專案頁被 CDN 快取時，名額數字可能是幾分鐘前的；需要即時數字的地方可以另外呼叫這個小端點，
# 它的快取時間很短（5 秒），把「大頁面長快取、小數字短快取」分開。
class RewardsController < ApplicationController
  include PublicCacheable

  # 選方案頁 /projects/:slug/rewards（讀取，可快取）
  def index
    @project = Project.find_by!(slug: params[:project_slug])
    allow_public_cache!
    @rewards = @project.rewards
  end

  def stock
    reward = Reward.find(params[:id])
    allow_public_cache!(browser_ttl: 5, cdn_ttl: 5)
    render json: { reward_id: reward.id, remaining: reward.remaining_quota, total: reward.quota_total }
  end
end
