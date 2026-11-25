require "test_helper"

# 假金流送 callback：開發環境用真的 HTTP POST（測試環境平常走程式內呼叫，這裡特別測 HTTP 這條路）
class FakeGatewayNotifierTest < ActiveSupport::TestCase
  setup do
    @payment = place_order!(create_reward).latest_payment
    @settings = Rails.configuration.x.fake_gateway
    @original_delivery = @settings.delivery
    @settings.delivery = :http
  end

  teardown { @settings.delivery = @original_delivery }

  FakeResponse = Struct.new(:code, :body)
  OK = FakeResponse.new("200", "{}")

  test "以 HTTP POST 送到 /payments/callbacks/fake，帶正確簽章" do
    sent = nil
    stub_method(Net::HTTP, :post, ->(uri, body, headers) { sent = [uri, body, headers]; OK }) do
      Payments::FakeGatewayNotifier.deliver(@payment, status: "success", event_id: "evt_http")
    end

    uri, body, headers = sent
    assert_equal "/payments/callbacks/fake", uri.path
    assert_equal "evt_http", JSON.parse(body)["event_id"]
    assert Payments::Signature.verify!(secret: @settings.secret, timestamp: headers["X-Timestamp"],
                                       signature: headers["X-Signature"], body: body)
  end

  test "背景工作重試時沿用同一個 event_id" do
    event_ids = []
    stub_method(Net::HTTP, :post, ->(_uri, body, _headers) { event_ids << JSON.parse(body)["event_id"]; OK }) do
      2.times { DeliverFakeCallbackJob.perform_now(@payment.id, "success", event_id: "evt_retry") }
    end
    assert_equal %w[evt_retry evt_retry], event_ids
  end
end
