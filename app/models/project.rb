# 募資專案。底下有多個回饋方案（rewards）、加購商品、折扣碼。
class Project < ApplicationRecord
  has_many :rewards, -> { order(:position, :id) }, dependent: :destroy
  has_many :addons, -> { order(:position, :id) }, dependent: :destroy
  has_many :discount_codes, dependent: :destroy
  has_many :orders

  validates :slug, :title, :currency, presence: true

  # 網址用 slug，例如 /projects/mountain-map
  def to_param = slug
end
