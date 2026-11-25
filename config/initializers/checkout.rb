# 結帳系統的設定集中在這裡，用環境變數覆寫。
# 讀取方式：Rails.configuration.x.checkout.xxx

Rails.application.configure do
  # 付款期限：信用卡 15 分鐘、ATM 3 天（4320 分鐘）
  # Demo 時可以 ATM_EXPIRE_MINUTES=1 把 ATM 期限縮短成 1 分鐘
  config.x.checkout.card_expire_minutes = ENV.fetch("CARD_EXPIRE_MINUTES", 15).to_i
  config.x.checkout.atm_expire_minutes  = ENV.fetch("ATM_EXPIRE_MINUTES", 4320).to_i

  # 加碼贊助上限
  config.x.checkout.max_donation = BigDecimal("100000")

  # 假金流與系統之間簽章用的密鑰。
  # 正式環境一定要用環境變數設定；開發與測試環境有預設值方便直接跑。
  config.x.fake_gateway.secret =
    if Rails.env.production?
      ENV.fetch("FAKE_GATEWAY_SECRET")
    else
      ENV.fetch("FAKE_GATEWAY_SECRET", "dev-only-fake-gateway-secret")
    end

  # 假金流把 callback 送到哪裡（就是本系統自己）
  config.x.fake_gateway.callback_base_url =
    ENV.fetch("APP_BASE_URL", "http://localhost:#{ENV.fetch('PORT', 3000)}")

  # 假金流送 callback 的方式：
  #   :http   → 真的用 HTTP POST 打到 /payments/callbacks/fake（貼近真實金流）
  #   :inline → 直接在程式內呼叫處理流程（測試環境用，因為測試時沒有固定網址的伺服器）
  config.x.fake_gateway.delivery = Rails.env.test? ? :inline : :http
end
