# 給逾期處理用的「部分索引」（spec §3.9、§6.7）。
#
# 逾期處理每次都要排除「有需人工處理付款」的訂單，也就是找出 status = 'needs_review' 的付款。
# 沒有索引時，資料庫要把整張付款表從頭翻到尾；付款紀錄會一直累積，越跑越慢。
#
# 為什麼是「部分」索引：需要人工處理的付款極少，只把這幾筆放進索引，
# 索引很小，一般付款的寫入也幾乎不受影響（狀態不是 needs_review 的付款根本不進索引）。
#
# 為什麼另開一個 migration、不改原本那個：已經建好資料庫的人只要執行 db:migrate 就能補上，
# 不用把整個資料庫砍掉重建。
class AddNeedingReviewIndexToPayments < ActiveRecord::Migration[8.1]
  def change
    add_index :payments, :order_id, where: "status = 'needs_review'", name: "index_payments_needing_review"
  end
end
