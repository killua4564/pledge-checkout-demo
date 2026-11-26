# 付款：一張訂單的一次「付款嘗試」。
#
# status:
#   pending       等待金流結果
#   paid          金流確認成功
#   failed        金流回報失敗
#   needs_review  需要人工處理，原因記在 review_reason：
#                   late_payment     訂單已過期／取消後才收到付款 → 要退款
#                   amount_mismatch  callback 金額和我們送出的不同
class Payment < ApplicationRecord
  STATUSES = %w[pending paid failed needs_review].freeze
  REVIEW_REASONS = %w[late_payment amount_mismatch].freeze

  belongs_to :order
  has_many :payment_events, dependent: :nullify

  validates :status, inclusion: { in: STATUSES }
  validates :review_reason, inclusion: { in: REVIEW_REASONS }, allow_nil: true

  def needs_review? = status == "needs_review"

  # 標記為需要人工處理。已經 paid 的付款不改（錢已正確入帳，後到的異常通知不能推翻終點狀態，spec §6.5）。
  #
  # 用條件更新（WHERE status <> 'paid'），不用「先讀狀態、再決定要不要改」：
  # 成功通知和異常通知同時到時，先讀再改可能讀到舊狀態，把剛變成 paid 的付款蓋掉。
  # 回傳 true 代表有標記到；false 代表付款已是 paid，沒有改。
  def flag_for_review!(reason)
    raise ArgumentError, "不認識的原因：#{reason}" unless REVIEW_REASONS.include?(reason)

    now = Time.current
    changed = Payment.where(id: id).where.not(status: "paid")
                     .update_all(status: "needs_review", review_reason: reason, updated_at: now)
    reload
    changed.positive?
  end
end
