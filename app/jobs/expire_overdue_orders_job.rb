# 逾期處理包成 job，之後若改用排程工具（例如 Solid Queue 的週期任務）可以直接呼叫。
class ExpireOverdueOrdersJob < ApplicationJob
  queue_as :default

  def perform
    Orders::ExpireOverdue.call
  end
end
