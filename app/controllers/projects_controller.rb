# 專案介紹頁（讀取，可快取）
class ProjectsController < ApplicationController
  include PublicCacheable

  def show
    @project = Project.find_by!(slug: params[:slug])
    allow_public_cache!
  end
end
