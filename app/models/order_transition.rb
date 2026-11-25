# 訂單狀態變更紀錄：誰（原因）在什麼時候把訂單從哪個狀態改成哪個狀態。
class OrderTransition < ApplicationRecord
  belongs_to :order
end
