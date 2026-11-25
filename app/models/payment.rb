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

  def flag_for_review!(reason)
    update!(status: "needs_review", review_reason: reason)
  end
end
