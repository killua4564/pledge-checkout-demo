# 折扣碼：由提案團隊發行，只能用在自己的專案。目前只有「折固定金額」。
class DiscountCode < ApplicationRecord
  belongs_to :project

  before_validation { self.code = self.class.normalize(code) }
  validates :code, presence: true
  validates :amount, numericality: { greater_than: 0 }

  # 比對前先正規化：去掉前後空白、轉大寫。" save500 " → "SAVE500"
  def self.normalize(text) = text.to_s.strip.upcase

  # 在指定專案找折扣碼並檢查是否可用。
  # 回傳 [折扣碼, nil]（可用）或 [nil, 錯誤原因]（不可用）
  def self.lookup(project:, text:, now: Time.current)
    normalized = normalize(text)
    return [nil, nil] if normalized.empty?   # 沒輸入，不算錯

    code = project.discount_codes.find_by(code: normalized)
    return [nil, "折扣碼不存在或不適用此專案"] unless code
    return [nil, "折扣碼不在有效期間"] unless code.active_at?(now)

    [code, nil]
  end

  def active_at?(time)
    (starts_at.nil? || starts_at <= time) && (ends_at.nil? || time <= ends_at)
  end
end
