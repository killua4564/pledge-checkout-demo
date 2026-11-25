# 網址分成「讀」和「寫」兩區（docs/spec.md §7）：
#   讀（可以放 Cloudflare 快取）：首頁、專案頁、選方案頁、剩餘名額
#   寫（不可快取）：結帳頁、金額預覽、建立訂單、訂單頁、金流 callback
Rails.application.routes.draw do
  # ── 讀 ──
  root "home#index"

  resources :projects, only: :show, param: :slug do
    # 選方案頁：/projects/:slug/rewards
    get "rewards", to: "rewards#index", as: :rewards
  end

  get "rewards/:id/stock", to: "rewards#stock", as: :reward_stock

  # ── 寫 ──
  # 結帳頁：/projects/:slug/checkout?reward=<方案 ID>
  # 和選方案頁用「不同路徑」，CDN 規則只要寫「/checkout 不快取」，不用判斷網址參數
  get  "projects/:project_slug/checkout", to: "checkouts#show", as: :project_checkout
  get  "go", to: "home#go", as: :go                       # 首頁輸入方案 ID 後轉址到結帳頁
  post "checkout/quote", to: "quotes#create", as: :checkout_quote

  resources :orders, only: [:create, :show], param: :public_id do
    post :cancel, on: :member
  end

  post "payments/callbacks/:provider", to: "payments/callbacks#create", as: :payment_callback

  # ── 假金流（只在開發、測試環境存在） ──
  if Rails.env.local?
    namespace :fake_gateway do
      get  "pay/:trade_no", to: "payments#show", as: :pay
      post "pay/:trade_no", to: "payments#decide"
      get  "atm/:trade_no", to: "atm#show", as: :atm
      post "atm/:trade_no", to: "atm#transfer"
      get  "debug", to: "debug#index", as: :debug
      post "debug/:payment_id/:scenario", to: "debug#create", as: :debug_action
      post "debug/expire_overdue", to: "debug#expire_overdue", as: :debug_expire_overdue
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
