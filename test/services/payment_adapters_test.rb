require "test_helper"

# G. 付款 adapter
class PaymentAdaptersTest < ActiveSupport::TestCase
  teardown { Payments::Registry.reset! }

  test "G1 依付款方式取得對應的 adapter" do
    assert_instance_of Payments::Adapters::FakeCreditCard, Payments::Registry.fetch("credit_card")
    assert_instance_of Payments::Adapters::FakeAtm, Payments::Registry.fetch("atm")
    assert_instance_of Payments::Adapters::Aftee, Payments::Registry.fetch("aftee")
  end

  test "G2 AFTEE 尚未開放" do
    refute Payments::Registry.available?("aftee")
    assert_raises(Payments::NotAvailable) { Payments::Registry.fetch("aftee").create_payment(nil) }
  end

  test "G3 每個 adapter 都實作相同的介面" do
    Payments::Registry.all.each do |adapter|
      %i[method_key label provider available? create_payment parse_callback refund gateway_amount].each do |name|
        assert_respond_to adapter, name
      end
    end
  end

  test "G4 註冊新的 adapter 就能使用，不需要修改訂單或狀態機" do
    test_adapter = Class.new(Payments::Adapters::FakeCreditCard) { def method_key = "line_pay" }
    stub_const = "LinePayTestAdapter"
    Object.const_set(stub_const, test_adapter)
    Payments::Registry.register("line_pay", stub_const)

    order = place_order!(create_reward, payment_method: "line_pay")
    assert_equal "line_pay", order.payment_method
    assert_equal "line_pay", order.latest_payment.payment_method
  ensure
    Object.send(:remove_const, stub_const) if Object.const_defined?(stub_const)
  end

  test "G5 退款是擴充點，目前丟 NotImplementedError" do
    assert_raises(NotImplementedError) { Payments::Registry.fetch("credit_card").refund(nil) }
  end

  test "G6 金額轉成金流格式：依幣別小數位數" do
    adapter = Payments::Registry.fetch("credit_card")
    assert_equal "2980", adapter.gateway_amount(BigDecimal("2980.00"), "TWD")
    assert_equal "19.90", adapter.gateway_amount(BigDecimal("19.9"), "USD")
  end
end
