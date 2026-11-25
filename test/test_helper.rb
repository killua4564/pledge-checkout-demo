ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

# 測試用的資料建立工具。每個測試自己建立需要的資料，讀測試時一眼就知道情境是什麼。
module TestData
  def create_project(slug: "project-#{SecureRandom.hex(4)}", currency: "TWD")
    Project.create!(slug: slug, title: "測試專案 #{slug}", currency: currency)
  end

  # 建立方案，並附上三種運費：本島 0、離島 100（加購 +30）、海外 300（加購 +50）
  def create_reward(project: create_project, price: 2980, quota_total: 200, quota_taken: 0, list_price: nil, title: "收藏套組")
    reward = project.rewards.create!(title: title, price: price, list_price: list_price,
                                     quota_total: quota_total, quota_taken: quota_taken)
    reward.shipping_rates.create!(region: "tw_main",   label: "台灣（本島）", fee: 0,   addon_fee: 0)
    reward.shipping_rates.create!(region: "tw_island", label: "台灣（離島）", fee: 100, addon_fee: 30)
    reward.shipping_rates.create!(region: "overseas",  label: "海外",         fee: 300, addon_fee: 50)
    reward
  end

  def create_addon(project:, price: 300, title: "加購小物")
    project.addons.create!(title: title, price: price)
  end

  def create_code(project:, code: "SAVE500", amount: 500, starts_at: nil, ends_at: nil)
    project.discount_codes.create!(code: code, amount: amount, starts_at: starts_at, ends_at: ends_at)
  end

  # 一份填寫正確的結帳表單，可用 overrides 改掉想測的欄位
  def checkout_params(reward, **overrides)
    {
      checkout_token: SecureRandom.uuid,
      reward_id: reward.id,
      payment_method: "credit_card",
      ship_region: "tw_main",
      ship_city: "新北市",
      ship_district: "新莊區",
      ship_zip: "242",
      ship_address: "中正路 1 號",
      recipient_name: "王小明",
      recipient_phone: "0912345678",
      invoice_type: "personal",
    }.merge(overrides)
  end

  # 用 Orders::Create 建立一張訂單（失敗會直接讓測試失敗，並顯示原因）
  def place_order!(reward, **overrides)
    result = Orders::Create.call(reward: reward, params: checkout_params(reward, **overrides))
    assert result.success?, "建立訂單失敗：#{result.errors.inspect}"
    result.order
  end

  # 組出一則假金流 callback：回傳 [內文, headers]
  def signed_callback(payment, status: "success", event_id: "evt_#{SecureRandom.hex(6)}", amount: payment.amount,
                      secret: Rails.configuration.x.fake_gateway.secret, timestamp: Time.current.to_i.to_s)
    body = { event_id: event_id, trade_no: payment.provider_trade_no, status: status,
             amount: Money.round(amount, payment.currency).to_s("F"), currency: payment.currency }.to_json
    headers = {
      "X-Timestamp" => timestamp,
      "X-Signature" => Payments::Signature.sign(secret: secret, timestamp: timestamp, body: body),
    }
    [body, headers]
  end

  # 在 block 執行期間，暫時把某個物件的方法換掉（例如模擬「寫入資料庫失敗」），結束後還原
  def stub_method(object, name, replacement)
    had_own = object.singleton_methods(false).include?(name)
    original = object.method(name)
    object.define_singleton_method(name, &replacement)
    yield
  ensure
    if had_own
      object.define_singleton_method(name, original)
    else
      object.singleton_class.send(:remove_method, name)
    end
  end

  # 直接呼叫 callback 處理流程（不經 HTTP）
  def deliver_callback(payment, **options)
    body, headers = signed_callback(payment, **options)
    Payments::ProcessCallback.call(provider: "fake", raw_body: body, headers: headers)
  end
end

module ActiveSupport
  class TestCase
    # 多個行程平行跑測試；每個行程有自己的 SQLite 資料庫
    parallelize(workers: :number_of_processors)

    include TestData
  end
end

class ActionDispatch::IntegrationTest
  include TestData
end
