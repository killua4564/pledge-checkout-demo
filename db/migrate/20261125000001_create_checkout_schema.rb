# 整個結帳系統的資料表，集中在一個 migration 方便閱讀。
# 對照文件：docs/spec.md §3
#
# 金額欄位一律 decimal(12, 2)：不用 float，避免 0.1 + 0.2 = 0.30000000000000004 這類誤差。
# 幣別的小數位數（TWD 0 位、USD 2 位）由 app/lib/money.rb 負責捨入。
class CreateCheckoutSchema < ActiveRecord::Migration[8.1]
  def change
    # ── 專案：一個募資專案，底下有多個回饋方案 ──
    create_table :projects do |t|
      t.string  :slug, null: false               # 網址用，例如 /projects/mountain-map
      t.string  :title, null: false
      t.string  :summary
      t.text    :description
      t.string  :cover_image_url                 # 專案頁封面圖（一張）
      t.string  :currency, null: false, default: "TWD"
      t.decimal :funding_goal, precision: 12, scale: 2   # 目標金額（顯示用；也是日後「到期結算」的擴充點）
      t.datetime :starts_at
      t.datetime :ends_at
      t.timestamps
    end
    add_index :projects, :slug, unique: true

    # ── 回饋方案：結帳頁的「商品 ID」就是這張表的 id ──
    create_table :rewards do |t|
      t.references :project, null: false, foreign_key: true
      t.string  :title, null: false
      t.text    :description
      t.string  :image_url
      t.decimal :list_price, precision: 12, scale: 2      # 預定售價（只用來顯示「幾折」）
      t.decimal :price, precision: 12, scale: 2, null: false  # 贊助價（真正計算用）
      t.integer :quota_total, null: false                 # 名額上限
      t.integer :quota_taken, null: false, default: 0     # 已佔用（含「待付款」保留中的訂單）
      t.date    :estimated_delivery_on
      t.integer :position, null: false, default: 0
      t.timestamps

      # 資料庫層的最後防線：就算程式寫錯，資料庫也不允許超賣或變負數
      t.check_constraint "quota_taken >= 0 AND quota_taken <= quota_total", name: "rewards_quota_within_limit"
    end

    # ── 加購商品：屬於專案，所有方案都能加購；每個加購每張訂單最多 1 個 ──
    create_table :addons do |t|
      t.references :project, null: false, foreign_key: true
      t.string  :title, null: false
      t.decimal :price, precision: 12, scale: 2, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    # ── 運費：跟著方案、依地區設定 ──
    create_table :shipping_rates do |t|
      t.references :reward, null: false, foreign_key: true
      t.string  :region, null: false          # tw_main（本島）/ tw_island（離島）/ overseas（海外）
      t.string  :label, null: false           # 畫面顯示用，例如「台灣（本島）」
      t.decimal :fee, precision: 12, scale: 2, null: false, default: 0        # 方案本身的運費
      t.decimal :addon_fee, precision: 12, scale: 2, null: false, default: 0  # 有選加購時額外加收
      t.timestamps
    end
    add_index :shipping_rates, [:reward_id, :region], unique: true

    # ── 折扣碼：由提案團隊發行，只能用在自己的專案；目前只有「折固定金額」 ──
    create_table :discount_codes do |t|
      t.references :project, null: false, foreign_key: true
      t.string  :code, null: false            # 一律存大寫，比對時不分大小寫
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.datetime :starts_at                   # null = 不限
      t.datetime :ends_at                     # null = 不限
      t.timestamps
    end
    add_index :discount_codes, [:project_id, :code], unique: true

    # ── 訂單 ──
    create_table :orders do |t|
      t.string :public_id, null: false        # UUID，網址用；不用流水號，避免被猜到別人的訂單
      t.string :checkout_token, null: false   # 結帳頁產生的 UUID；同一次送出只會建立一張訂單
      t.references :project, null: false, foreign_key: true
      t.references :reward, null: false, foreign_key: true
      t.string :status, null: false, default: "pending_payment"
      t.string :currency, null: false

      # 金額快照：下單當下算好存起來，之後方案改價也不影響舊訂單
      t.decimal :reward_amount,   precision: 12, scale: 2, null: false
      t.decimal :addons_amount,   precision: 12, scale: 2, null: false, default: 0
      t.decimal :discount_amount, precision: 12, scale: 2, null: false, default: 0
      t.decimal :shipping_amount, precision: 12, scale: 2, null: false, default: 0
      t.decimal :donation_amount, precision: 12, scale: 2, null: false, default: 0
      t.decimal :total_amount,    precision: 12, scale: 2, null: false

      t.string   :payment_method, null: false   # credit_card / atm / free（0 元訂單）
      t.datetime :expires_at                    # 付款期限，逾期由 rake task 轉為 expired

      # 收件資訊
      t.string :ship_region, null: false
      t.string :ship_city
      t.string :ship_district
      t.string :ship_zip
      t.string :ship_address
      t.string :recipient_name
      t.string :recipient_phone

      # 發票資訊（只存，不串接）
      t.string :invoice_type, null: false, default: "personal"   # personal / company
      t.string :carrier_code
      t.string :company_tax_id
      t.string :company_title

      # 各狀態發生的時間
      t.datetime :paid_at
      t.datetime :failed_at
      t.datetime :cancelled_at
      t.datetime :expired_at
      t.timestamps
    end
    add_index :orders, :public_id, unique: true
    add_index :orders, :checkout_token, unique: true
    add_index :orders, [:status, :expires_at]   # 給「找出逾期訂單」用

    # ── 訂單的加購明細（快照） ──
    create_table :order_addons do |t|
      t.references :order, null: false, foreign_key: true
      t.references :addon, null: false, foreign_key: true
      t.string  :title, null: false
      t.decimal :price, precision: 12, scale: 2, null: false
      t.timestamps
    end
    add_index :order_addons, [:order_id, :addon_id], unique: true   # 每個加購最多 1 個

    # ── 訂單使用的折扣（快照）：一碼一列 ──
    create_table :order_discounts do |t|
      t.references :order, null: false, foreign_key: true, index: { unique: true }  # 目前一單一碼；拿掉 unique 就能一單多碼
      t.references :discount_code, null: false, foreign_key: true
      t.string  :code, null: false
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.timestamps
    end

    # ── 付款：一張訂單的「付款嘗試」 ──
    create_table :payments do |t|
      t.references :order, null: false, foreign_key: true
      t.string  :payment_method, null: false      # credit_card / atm（不取名 method，避免和 Ruby 內建方法撞名）
      t.string  :provider, null: false            # 金流商代號，目前只有 fake
      t.string  :provider_trade_no, null: false   # 金流端的交易編號，callback 用它找回這筆付款
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.string  :currency, null: false
      t.string  :status, null: false, default: "pending"   # pending / paid / failed / needs_review
      t.string  :review_reason                    # late_payment / amount_mismatch
      t.string  :virtual_account                  # ATM 虛擬帳號
      t.datetime :pay_deadline                    # ATM 繳費期限
      t.json    :payload, null: false, default: {}  # 金流原始資料（除錯用）
      t.timestamps
    end
    add_index :payments, [:provider, :provider_trade_no], unique: true

    # ── 收到的 callback：(provider, event_id) 唯一 → 同一則通知只會被處理一次（冪等） ──
    create_table :payment_events do |t|
      t.string  :provider, null: false
      t.string  :event_id                         # 簽章錯誤時無法信任內容，會是 null
      t.references :payment, foreign_key: true
      t.boolean :signature_valid, null: false
      t.text    :raw_body
      t.string  :result, null: false              # applied / duplicate / rejected_signature / rejected_amount / ignored / malformed
      t.string  :note                             # 補充原因，例如「訂單已付款，忽略」
      t.timestamps
    end
    add_index :payment_events, [:provider, :event_id], unique: true

    # ── 訂單狀態變更紀錄（稽核用） ──
    create_table :order_transitions do |t|
      t.references :order, null: false, foreign_key: true
      t.string :from_status, null: false
      t.string :to_status, null: false
      t.string :reason
      t.timestamps
    end
  end
end
