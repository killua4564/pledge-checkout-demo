# 訂單的加購明細。title、price 是下單當下的快照。
class OrderAddon < ApplicationRecord
  belongs_to :order
  belongs_to :addon
end
