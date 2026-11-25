class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # 預設所有頁面都「不可快取」（結帳、訂單這類寫入頁面）。
  # 可以快取的讀取頁面會在 PublicCacheable 裡改掉這個設定。
  before_action { response.headers["Cache-Control"] = "no-store" }

  rescue_from ActiveRecord::RecordNotFound do
    render "errors/not_found", status: :not_found
  end
end
