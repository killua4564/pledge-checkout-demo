# 訂單。
#
# 狀態機（對照 docs/spec.md §4）：
#
#                   ┌── pay ────▶ paid
#                   ├── fail ───▶ failed
#   pending_payment ┼── cancel ─▶ cancelled
#                   └── expire ─▶ expired
#
# 只允許上面四種轉換，其他一律拒絕。真正執行轉換的程式在 app/services/orders/transition.rb。
class Order < ApplicationRecord
  # 非法的狀態轉換（例如已付款的訂單想改成已取消）
  class InvalidTransition < StandardError; end

  STATUSES = %w[pending_payment paid failed cancelled expired].freeze

  # 轉換表：事件名稱 => 從哪個狀態、到哪個狀態。
  # 日後要加「退款」，只要在這裡多一行 refund: { from: "paid", to: "refunded" }
  TRANSITIONS = {
    pay:    { from: "pending_payment", to: "paid" },
    fail:   { from: "pending_payment", to: "failed" },
    cancel: { from: "pending_payment", to: "cancelled" },
    expire: { from: "pending_payment", to: "expired" },
  }.freeze

  # 這些狀態代表訂單已失效，要把名額還回去
  RELEASING_STATUSES = %w[failed cancelled expired].freeze

  STATUS_LABELS = {
    "pending_payment" => "待付款",
    "paid"            => "已付款",
    "failed"          => "付款失敗",
    "cancelled"       => "已取消",
    "expired"         => "已過期",
  }.freeze

  PAYMENT_METHOD_LABELS = { "credit_card" => "信用卡", "atm" => "ATM 轉帳", "free" => "免付款（0 元）" }.freeze

  belongs_to :project
  belongs_to :reward
  has_many :order_addons, dependent: :destroy
  has_one  :order_discount, dependent: :destroy
  has_many :payments, -> { order(:id) }, dependent: :destroy
  has_many :order_transitions, -> { order(:id) }, dependent: :destroy

  validates :status, inclusion: { in: STATUSES }

  # 建立時自動產生 UUID 作為對外編號
  before_validation(on: :create) { self.public_id ||= SecureRandom.uuid }

  # 網址用 public_id（UUID），不用流水號 id
  def to_param = public_id

  STATUSES.each do |name|
    define_method(:"#{name}?") { status == name }
  end

  def status_label = STATUS_LABELS.fetch(status)
  def payment_method_label = PAYMENT_METHOD_LABELS.fetch(payment_method, payment_method)

  def latest_payment = payments.last

  # 訂單頁要不要自動更新：只有「幾秒內就會有結果」的付款（信用卡）才需要。
  # ATM 可能幾天後才轉帳，一直自動更新只是白白消耗伺服器和手機電量，改由使用者手動重新整理。
  def auto_refresh? = pending_payment? && payment_method != "atm"

  # 需要人工處理的付款（逾期才付款、金額不符）
  def payment_needing_review = payments.find { |p| p.status == "needs_review" }

  def money(amount) = Money.format(amount, currency)
end
