# 加購商品。屬於專案，所有方案都能加購；每張訂單每個加購最多 1 個。
class Addon < ApplicationRecord
  belongs_to :project
end
