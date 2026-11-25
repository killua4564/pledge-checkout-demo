# 「讀取頁面」用：讓頁面可以被 CDN（例如 Cloudflare）快取。
#
# 熱門專案時，大部分流量都在看專案頁、選方案頁。這些頁面對每個人都長得一樣，
# 只要回應裡沒有個人化的東西，CDN 就能直接回傳快取，不用每次都打到我們的伺服器。
#
# 所以這類頁面要做到：
#   1. 不寫 session cookie（有 Set-Cookie 的回應，CDN 不會快取）
#   2. 不放 CSRF token（每個人的 token 都不同，放了就不能共用）
#   3. 回應 Cache-Control: public，告訴 CDN 可以快取
#
# 本專案只把頁面「準備好」可以被快取，實際的 Cloudflare 設定見 docs/decisions.md。
module PublicCacheable
  extend ActiveSupport::Concern

  # 瀏覽器快取 60 秒；CDN（s-maxage）快取 5 分鐘
  BROWSER_TTL = 60
  CDN_TTL = 300

  private

  # 在 action 裡呼叫，宣告這個回應可以公開快取
  def allow_public_cache!(browser_ttl: BROWSER_TTL, cdn_ttl: CDN_TTL)
    request.session_options[:skip] = true          # 不讀寫 session，所以不會有 Set-Cookie
    @public_cacheable = true                       # layout 看到這個就不輸出 CSRF token
    response.headers["Cache-Control"] = "public, max-age=#{browser_ttl}, s-maxage=#{cdn_ttl}"
  end
end
