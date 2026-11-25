# 訂單使用的折扣（一碼一列）：記錄「用了哪張碼、折了多少錢」的快照。
# 目前資料庫以 order_id 唯一索引限制一張訂單一張碼；拿掉這個限制就能一單多碼。
class OrderDiscount < ApplicationRecord
  belongs_to :order
  belongs_to :discount_code
end
