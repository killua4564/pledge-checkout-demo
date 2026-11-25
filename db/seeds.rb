# Demo 用資料。執行 bin/rails db:seed（或 bin/rails db:reset 清空重來）。
# 重複執行會先清掉舊資料，所以隨時可以重置 Demo 狀態。

puts "清除舊資料…"
models = [PaymentEvent, Payment, OrderTransition, OrderDiscount, OrderAddon, Order,
          DiscountCode, ShippingRate, Addon, Reward, Project]
models.each(&:delete_all)

# 讓 id 從 1 重新開始（SQLite 的流水號記在 sqlite_sequence），重置後方案 ID 固定是 1～5，方便 Demo
connection = ActiveRecord::Base.connection
if connection.adapter_name.match?(/sqlite/i)
  table_list = models.map { |model| connection.quote(model.table_name) }.join(", ")
  connection.execute("DELETE FROM sqlite_sequence WHERE name IN (#{table_list})")
end

# 每個方案都有三種運費：本島免運、離島、海外
def add_shipping_rates(reward)
  reward.shipping_rates.create!(region: "tw_main",   label: "台灣（本島）", fee: 0,   addon_fee: 0)
  reward.shipping_rates.create!(region: "tw_island", label: "台灣（離島）", fee: 100, addon_fee: 30)
  reward.shipping_rates.create!(region: "overseas",  label: "海外",         fee: 300, addon_fee: 50)
end

# ── 專案 1：主要 Demo 專案 ──
book = Project.create!(
  slug: "mountain-map",
  title: "《山城慢遊》手繪地圖書",
  summary: "用手繪地圖和散步路線，帶你走進山城的巷弄與老店。（Demo 用虛構專案）",
  description: "這是 Demo 用的虛構專案，用來展示贊助結帳流程。\n\n專案內容包含地圖書、摺頁大地圖與明信片。",
  currency: "TWD",
  funding_goal: 500_000,
  starts_at: 30.days.ago,
  ends_at: 30.days.from_now
)

bundle = book.rewards.create!(
  title: "收藏套組",
  description: <<~TEXT,
    限時活動：輸入折扣碼「SAVE500」再折 500 元
    ➤ 地圖書兩冊
    ➤ 摺頁大地圖一張
    ➤ 明信片一組
    ➤ 集資限定貼紙
  TEXT
  list_price: 3725, price: 2980,               # 顯示「8 折」
  quota_total: 200, quota_taken: 190,          # 剩 10 份，展示「剩餘名額」
  estimated_delivery_on: Date.new(2027, 1, 31),
  position: 1
)
early = book.rewards.create!(
  title: "早鳥單本",
  description: "➤ 地圖書一冊\n➤ 早鳥限定書衣",
  list_price: 980, price: 800,
  quota_total: 100, quota_taken: 0,
  estimated_delivery_on: Date.new(2027, 1, 31),
  position: 2
)
last_seat = book.rewards.create!(
  title: "最後一席",
  description: "➤ 作者親簽版一冊\n➤ 只有 1 份，用來展示「搶最後一個名額」不會超賣",
  price: 1200,
  quota_total: 1, quota_taken: 0,
  estimated_delivery_on: Date.new(2027, 2, 28),
  position: 3
)
postcards = book.rewards.create!(
  title: "明信片組",
  description: "➤ 手繪明信片 8 張\n➤ 用 FREE800 可以看到「折扣不會超過方案金額」：只折 500",
  price: 500,
  quota_total: 300, quota_taken: 0,
  estimated_delivery_on: Date.new(2026, 12, 31),
  position: 4
)
[bundle, early, last_seat, postcards].each { |reward| add_shipping_rates(reward) }

book.addons.create!(title: "加購小物", price: 300, position: 1)
book.addons.create!(title: "書籤組", price: 100, position: 2)
book.addons.create!(title: "帆布袋", price: 250, position: 3)

book.discount_codes.create!(code: "SAVE500", amount: 500)
book.discount_codes.create!(code: "FREE800", amount: 800)   # 用在早鳥單本（800）剛好折到 0；用在明信片組（500）最多只折 500

book.discount_codes.create!(code: "EXPIRED", amount: 300, starts_at: 60.days.ago, ends_at: 1.day.ago)

# ── 專案 2：另一個專案，用來展示「折扣碼、加購只能用在自己的專案」 ──
game = Project.create!(
  slug: "island-boardgame",
  title: "島嶼桌遊 Demo",
  summary: "用來展示跨專案的限制。（Demo 用虛構專案）",
  description: "另一個虛構專案。",
  currency: "TWD",
  funding_goal: 300_000,
  starts_at: 10.days.ago,
  ends_at: 20.days.from_now
)
base_game = game.rewards.create!(title: "基本版", description: "➤ 桌遊一盒", price: 1200, quota_total: 300, quota_taken: 12,
                                 estimated_delivery_on: Date.new(2027, 3, 31), position: 1)
add_shipping_rates(base_game)
game.addons.create!(title: "擴充包", price: 400, position: 1)
game.discount_codes.create!(code: "GAME100", amount: 100)

puts "完成：#{Project.count} 個專案、#{Reward.count} 個方案。"
Reward.includes(:project).each do |reward|
  puts "  方案 ID #{reward.id}：#{reward.project.title} / #{reward.title}"
end
