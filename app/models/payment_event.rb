# 收到的每一則金流 callback 都記一筆。
# (provider, event_id) 在資料庫是唯一的：同一則通知第二次寫入會失敗，這就是「冪等」的核心。
class PaymentEvent < ApplicationRecord
  RESULTS = %w[applied duplicate rejected_signature rejected_amount ignored malformed].freeze

  belongs_to :payment, optional: true

  validates :result, inclusion: { in: RESULTS }
end
