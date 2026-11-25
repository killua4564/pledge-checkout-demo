require "test_helper"
require "capybara/selenium/driver"
require "capybara/selenium/driver_specializations/chrome_driver"

# 相容性修補：Capybara 3.40 在每個測試結束時，會請 Chrome 用 origin "*" 清除所有網站資料，
# 但新版 Chrome 不再接受 "*"。被拒絕時改成刪除所有 cookie，達到同樣「每個測試從乾淨狀態開始」的效果。
module ChromeStorageResetCompat
  private

  def execute_cdp(cmd, params = {})
    super
  rescue Selenium::WebDriver::Error::InvalidArgumentError
    raise unless cmd == "Storage.clearDataForOrigin"

    browser.manage.delete_all_cookies
  end
end
Capybara::Selenium::Driver::ChromeDriver.prepend(ChromeStorageResetCompat)

# 系統測試：開一個看不見的 Chrome（headless），像真人一樣點按鈕、填表單、檢查畫面。
class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [1400, 1000]

  # 系統測試裡，背景 job 要「立刻執行」，點完按鈕才看得到結果
  setup do
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :inline
  end

  teardown { ActiveJob::Base.queue_adapter = @original_queue_adapter }
end
