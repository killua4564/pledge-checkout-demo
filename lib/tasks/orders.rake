namespace :orders do
  desc "把逾期未付款的訂單轉為已過期，並釋放名額"
  task expire_overdue: :environment do
    result = Orders::ExpireOverdue.call
    puts "逾期處理完成：轉為已過期 #{result.expired} 筆，略過 #{result.skipped} 筆，失敗 #{result.failed} 筆"
  end
end
