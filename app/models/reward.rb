# 回饋方案。結帳頁的「商品 ID」就是方案的 id。
class Reward < ApplicationRecord
  belongs_to :project
  has_many :shipping_rates, -> { order(:id) }, dependent: :destroy

  delegate :currency, to: :project

  def remaining_quota = quota_total - quota_taken
  def sold_out? = remaining_quota <= 0

  # 顯示「8 折」「79 折」：贊助價 ÷ 預定售價。沒有預定售價就不顯示。
  def discount_label
    return nil if list_price.blank? || list_price <= price

    ratio = (price / list_price * 100).floor
    ratio % 10 == 0 ? "#{ratio / 10} 折" : "#{ratio} 折"
  end
end
