# pledge-checkout-demo — Spec

> 一個群眾募資平台「贊助結帳」流程的 Demo。各章節最後的「擴充」段落說明日後要加功能時從哪裡改。

## 1. 範圍

**做**：專案頁 → 選回饋方案 → 結帳（加購、加碼贊助、折扣碼、運費）→ 付款（信用卡、ATM 轉帳；AFTEE 只顯示「尚未開放」）→ 訂單結果頁。第三方金流以假金流（mock）取代。
**不做**：登入、後台、真實金流、真實發票串接（只存欄位）、撥款與退款、快取（只在文件說明位置）。

### 核心設計
| 設計 | 做法 |
|---|---|
| 金額由伺服器計算 | `Checkout::PriceCalculator` 是唯一算錢的地方；前端只送「選了什麼」，不送金額 |
| 訂單狀態機 | 轉換表＋條件更新，非法轉換拒絕 |
| Callback 驗簽與冪等 | HMAC-SHA256 簽章；`payment_events (provider, event_id)` 唯一索引 |
| 名額不超賣 | 原子化條件更新 `UPDATE … WHERE quota_taken < quota_total` |
| 讀寫分離 | 專案頁、選方案頁（讀，可快取）與結帳、訂單、callback（寫，不可快取）分開 |

---

## 2. 技術選型

| 項目 | 決定 | 理由 |
|---|---|---|
| 框架 | Rails 8.1，ERB 伺服器端渲染 | 指定；與目標團隊技術一致 |
| 前端互動 | Hotwire（Turbo + Stimulus）＋ importmap | 不需要 Node |
| CSS | tailwindcss-rails | 不需要 Node |
| DB | SQLite（WAL 模式＋busy_timeout） | clone 下來就能跑 |
| 背景工作 | ActiveJob `:async` ＋ rake task | 不需要 Redis；換 Solid Queue／Sidekiq 時程式不用改 |
| 測試 | Minitest ＋ 系統測試（Capybara ＋ 無頭 Chrome） | Rails 內建 |
| 狀態機 | 自己寫（約 40 行） | 並行安全性較好，見 §4.4 |
| 金額 | `decimal(12,2)` ＋ `currency` | 見 §2.1 |

### 2.1 金額型別
- 不用 float（二進位小數有誤差）。decimal 與「整數存最小單位」都是精確做法，這裡選 decimal，因為比較好讀。
- 各金流要的金額格式不同（例如 Stripe 收整數「分」、綠界收整數新台幣），格式轉換放在各金流的 adapter 裡做。
- 小數位數依幣別而定：`Money::PRECISION = { "TWD" => 0, "USD" => 2, "JPY" => 0 }`。計算完依幣別捨入。

### 2.2 換到正式環境（例如 Heroku）
| 本機 | 正式環境 | 業務程式要改嗎 |
|---|---|---|
| SQLite | Postgres | 不用。名額扣減、狀態轉換都是一般的條件 UPDATE，Postgres 一樣成立 |
| ActiveJob `:async` | Solid Queue／Sidekiq | 不用，只改設定 |
| 手動跑 `orders:expire_overdue` | Heroku Scheduler 定期執行 | 不用 |
| 假金流密鑰預設值 | `FAKE_GATEWAY_SECRET` 環境變數（production 沒設定就無法啟動） | 不用 |

**海外站**：金額已經是 decimal＋currency，捨入依 `Money::PRECISION`；運費依地區查表；各站可在 Registry 設定不同的金流 adapter。要補的是匯率與各站設定；快取部分，各站各自設定 CDN，快取鍵要包含網域。

---

## 3. 資料表

### 3.1 `projects`（專案）
| 欄位 | 說明 |
|---|---|
| slug (unique) | 網址 `/projects/:slug` |
| title, summary, description | 專案標題、短介紹、內容 |
| cover_image_url | 專案頁封面圖（一張） |
| currency | 預設 `TWD`，整個專案共用 |
| funding_goal, starts_at, ends_at | 顯示目標金額與募資期間；也是專案到期結算的擴充點 |

### 3.2 `rewards`（回饋方案；「商品 ID」＝方案 ID）
| 欄位 | 說明 |
|---|---|
| project_id | |
| title, description | 例：收藏套組；方案內容（含限時活動文字，例如「輸入 SAVE500 再折 500 元」） |
| image_url, null | 方案圖（一張；結帳頁左側摘要使用） |
| list_price, price | 預定售價／贊助價（decimal） |
| quota_total, quota_taken | 名額上限／已佔用（含待付款保留中的訂單） |
| estimated_delivery_on | 預計實現日 |
| position | 排序 |
| DB 約束 | CHECK `0 <= quota_taken <= quota_total` |

一個方案＝一份，可以是組合（例如「1 入組」「2 入組」），名額與價格都以「份」計算。

### 3.3 `addons`（加購商品）
`project_id, title, price, position`
- 屬於專案，該專案的所有方案都可以加購
- 可以選多個不同的加購，**每個加購最多 1 個**

### 3.4 `shipping_rates`（運費）
`reward_id, region(tw_main / tw_island / overseas), label, fee, addon_fee`
- 跟著方案設定（每個方案卡片上可標示「臺灣本島免運」）
- `shipping = fee + (有選加購 ? addon_fee : 0)`，對應結帳頁的「運費」與「加購選項運費」兩行
- **收件地點沒有預設值，必須由使用者主動選擇**。預設成本島的話，離島或海外的使用者沒注意到就送出，會用錯的運費成立訂單；伺服器也不替使用者補預設值

**擴充：超商取貨（或其他配送方式）**
收件地點其實是「配送方式」：每一列 `shipping_rates` 就是一個選項。要加超商取貨：
- `shipping_rates` 加 `delivery_kind`（`home` 宅配／`cvs` 超商／`overseas` 海外），`region` 增加例如 `tw_cvs`
- `delivery_kind` 決定結帳頁要顯示、驗證哪些欄位：`home` 要縣市＋鄉鎮市區＋地址；`cvs` 要門市（`orders` 加 `pickup_store_id`、`pickup_store_name`，由超商選店頁回填）；`overseas` 只要地址
- 運費計算（§5 步驟 4）完全不用改，因為它只看「選了哪一列」
- 是否提供某種配送方式，由該方案有沒有那一列決定（例如大型商品不建超商那一列）

### 3.5 `discount_codes`（折扣碼）
| 欄位 | 說明 |
|---|---|
| project_id | 必填：折扣碼由提案團隊發行，只能用在自己的專案 |
| code | 同一專案內唯一，比對時不分大小寫 |
| amount | 折抵的固定金額（例：200） |
| starts_at, ends_at | 有效期間（null＝不限） |

### 3.6 `order_discounts`（訂單使用的折扣）
`order_id, discount_code_id, code, amount`
- 記錄訂單用了哪張折扣碼、折了多少（快照）
- 本輪一張訂單只能用一張碼：`order_id` 設唯一索引。拿掉這個索引就能一單多碼，資料表不用改

### 3.7 `orders`
| 欄位 | 說明 |
|---|---|
| public_id (unique) | UUID，網址使用，無法用流水號猜到其他訂單 |
| checkout_token (unique) | 結帳頁產生的 UUID，同一次送出只建立一張訂單 |
| project_id, reward_id | |
| status | 見 §4 |
| currency | |
| reward_amount, addons_amount, discount_amount, shipping_amount, donation_amount, total_amount | 金額快照（decimal） |
| payment_method | `credit_card` / `atm` / `free`（0 元訂單） |
| expires_at | 付款期限（信用卡 15 分鐘、ATM 3 天，可設定） |
| ship_region, ship_city, ship_district, ship_zip, ship_address, recipient_name, recipient_phone | 收件資訊 |
| invoice_type, carrier_code, company_tax_id, company_title | 發票資訊（只存，不串接） |
| paid_at, failed_at, cancelled_at, expired_at | 狀態時間 |

`public_id` 與 `checkout_token` 分開存，因為兩者生命週期不同：`checkout_token` 代表「這一次送出」，每次進入結帳頁都會重新產生；`public_id` 代表「這張訂單」。如果共用同一個值，付款失敗後按上一頁重新送出，會被導回舊的失敗訂單。

### 3.8 `order_addons`
`order_id, addon_id, title, price`（快照）；`(order_id, addon_id)` 唯一

### 3.9 `payments`
| 欄位 | 說明 |
|---|---|
| order_id, method, provider(`fake`) | |
| provider_trade_no (unique) | callback 用它找到對應的付款 |
| amount, currency | |
| status | `pending` / `paid` / `failed` / `needs_review` |
| review_reason | `late_payment`（訂單已過期／取消後才付款）、`amount_mismatch`（金額不符） |
| virtual_account, pay_deadline | ATM 用 |
| payload | 金流原始回應（JSON） |

### 3.10 `payment_events`
`provider, event_id`（複合唯一）`, payment_id, signature_valid, raw_body, result(applied / duplicate / rejected_signature / rejected_amount / ignored / malformed), note, created_at`

### 3.11 `order_transitions`
`order_id, from_status, to_status, reason, created_at`

### 3.12 關聯
```
projects ─┬─< rewards ─┬─< shipping_rates
          │            └─< orders
          ├─< addons
          └─< discount_codes

orders ─┬─< order_addons >─ addons
        ├─< order_discounts >─ discount_codes
        ├─< payments ─< payment_events
        └─< order_transitions
```
（`A ─< B`：一個 A 有多個 B）

---

## 4. 訂單狀態

### 4.1 狀態
| 狀態 | 意義 | 佔名額 |
|---|---|---|
| `pending_payment` | 待付款 | 是 |
| `paid` | 已付款 | 是 |
| `failed` | 付款失敗 | 否 |
| `cancelled` | 使用者取消 | 否 |
| `expired` | 逾期未付，系統取消 | 否 |

### 4.2 合法轉換
```
                ┌── pay ────▶ paid
                ├── fail ───▶ failed
pending_payment ┼── cancel ─▶ cancelled
                └── expire ─▶ expired
```
- 其他轉換一律拒絕（`Order::InvalidTransition`），資料不變
- paid、failed、cancelled、expired 都是終點
- 0 元訂單：建立後在同一個交易內執行 `pay`（reason：金額為 0）

**擴充：募資失敗自動退款**
- `Order::TRANSITIONS` 加一行 `refund: { from: "paid", to: "refunded" }`
- 新增 `Projects::Settle`：找出 `ends_at` 已過、已付款總額未達 `funding_goal` 的專案，逐筆呼叫 `adapter.refund(payment)`，成功後 `Orders::Transition.call(order, :refund)`
- 退款結果也由金流非同步通知，沿用同一套驗簽與冪等（§6.5）
- 測試：未達標專案的已付款訂單全部轉 refunded；重複執行不會重複退款（轉換本身是條件更新）

### 4.3 轉換時做的事（`Orders::Transition`；callback、逾期、取消、0 元訂單共用）
在同一個資料庫交易內：
1. `UPDATE orders SET status = 新狀態 WHERE id = ? AND status = 'pending_payment'`。影響 0 列就丟例外並回復
2. 新狀態是 failed／cancelled／expired 時釋放名額：`UPDATE rewards SET quota_taken = quota_taken - 1 WHERE id = ? AND quota_taken > 0`
3. 寫入 `order_transitions` 與對應的時間欄位

第 1 步保證一張訂單只會離開 `pending_payment` 一次，所以名額不會重複釋放，也不需要額外的旗標欄位。

### 4.4 手寫狀態機 vs AASM

**手寫（採用）**
```ruby
class Order < ApplicationRecord
  TRANSITIONS = {
    pay:    { from: "pending_payment", to: "paid" },
    fail:   { from: "pending_payment", to: "failed" },
    cancel: { from: "pending_payment", to: "cancelled" },
    expire: { from: "pending_payment", to: "expired" },
  }.freeze
end

module Orders
  class Transition
    RELEASING = %w[failed cancelled expired].freeze

    def self.call(order, event, reason:)
      rule = Order::TRANSITIONS.fetch(event)
      Order.transaction do
        changed = Order.where(id: order.id, status: rule[:from])
                       .update_all(status: rule[:to], updated_at: Time.current)
        raise Order::InvalidTransition if changed.zero?
        Inventory.release(order.reward_id) if RELEASING.include?(rule[:to])
        OrderTransition.create!(order:, from_status: rule[:from], to_status: rule[:to], reason:)
      end
    end
  end
end
```

**AASM（對照）**
```ruby
class Order < ApplicationRecord
  include AASM

  aasm column: :status, requires_lock: true do
    state :pending_payment, initial: true
    state :paid, :failed, :cancelled, :expired

    event :pay do
      transitions from: :pending_payment, to: :paid
    end

    event :expire, after_commit: :release_quota do
      transitions from: :pending_payment, to: :expired
    end
    # fail、cancel 同理
  end
end

order.pay!       # 非法時丟 AASM::InvalidTransition
order.may_pay?   # => true / false
```

| | 手寫 | AASM |
|---|---|---|
| 並行 | 條件更新，不依賴資料列鎖 | 先讀狀態再存檔；要靠 `requires_lock`（`SELECT … FOR UPDATE`），**SQLite 不支援** |
| 可讀性 | 轉換表＋一個方法 | 宣告式 DSL，細節在 gem 裡 |
| 現成功能 | 需自己寫 | guard、`may_*?`、callback |
| 適合 | 狀態少、要清楚說明 | 狀態多、團隊已熟悉 |

結論：AASM 預設「先讀狀態、再存檔」，兩個請求同時讀到「待付款」會都成功；手寫版用一句條件 UPDATE 完成「檢查＋修改」，不依賴鎖。

### 4.5 名額：不超賣（`Inventory`）
- 下單時用一句 SQL 同時「檢查」和「扣除」：`UPDATE rewards SET quota_taken = quota_taken + 1 WHERE id = ? AND quota_taken < quota_total`。資料庫保證這句是原子的，影響 0 列就代表沒搶到 → 422「名額已被搶完」
- 不先 `SELECT` 再判斷：兩個人可能同時讀到「剩 1」而都通過
- DB 的 CHECK 約束 `quota_taken <= quota_total` 是最後一道防線
- 測試 D2、D3 用多條執行緒真的同時下單驗證

**擴充：加購商品有庫存上限**：`addons` 加 `quota_total／quota_taken`，在 `Orders::Create` 的同一個交易裡對每個加購做相同的條件更新，任一個不夠就整筆回復；訂單失效時在 `Orders::Transition` 一併釋放。

---

## 5. 金額計算（`Checkout::PriceCalculator`）

預覽（Stimulus 呼叫）與下單都使用同一個類別。

**輸入**：`reward, addon_ids[], discount_code, region, donation`

| 步驟 | 規則 |
|---|---|
| 1. 方案 | `reward_amount = reward.price` |
| 2. 加購 | `addons_amount = Σ 所選加購的 price`；加購必須屬於同專案，ID 重複則去重 |
| 3. 折扣 | 碼必須屬於本專案且在有效期間內；`discount = min(code.amount, reward_amount)` |
| 4. 運費 | `fee + (有加購 ? addon_fee : 0)`，依方案與收件地點查表；**還沒選收件地點時運費是「未知」** |
| 5. 加碼贊助 | 0 ～ 100,000，符合幣別小數位數（TWD 只能是整數）；空白視為 0 |
| 6. 總額 | `reward + addons − discount + shipping + donation`，依幣別捨入 |

- 折扣只折方案金額，不折加購、運費、加碼贊助
- 折扣上限是方案金額，所以總額不會是負數；總額為 0 時走 0 元訂單流程
- 折扣碼無效（不存在、不屬於本專案、不在期間內）時：預覽顯示原因、折扣為 0；**下單時拒絕並提示**
- 範例：收藏套組 2980 ＋ 加購 300 ＝ 3280；再輸入 `SAVE500` ＝ 2780
- **還沒選收件地點**：預覽的運費顯示「（未知）」，總額先不含運費並註明「未含運費」；這時不能下單（§7.2）
- 前端不算錢：欄位變動時把「選了什麼」送到 `POST /checkout/quote`，伺服器回傳算好的金額 HTML 片段

**擴充：百分比折扣碼（例：9 折，最多折 300）**
- `discount_codes` 加 `kind`（`fixed`／`percent`）與 `max_amount`
- 步驟 3 依 `kind` 計算：`percent` 用「方案金額 × 比例」並依幣別捨去，再套 `max_amount`，最後仍不超過方案金額
- `order_discounts` 只記「折了多少」，不用改
- 測試：有小數時捨去、上限封頂、總額不為負

---

## 6. 付款流程

### 6.1 Adapter
```
Payments::Registry
  credit_card → Payments::Adapters::FakeCreditCard
  atm         → Payments::Adapters::FakeAtm
  aftee       → Payments::Adapters::Aftee      # available? = false

介面：available? / create_payment(order) / parse_callback(request) / refund(payment)
refund 目前丟 NotImplementedError（退款擴充點）
```

**擴充：開放 AFTEE（或接上真實金流）**：在 `Payments::Adapters::Aftee` 實作 `create_payment`（呼叫對方 API、取得付款頁網址）與 `parse_callback`（依對方文件驗簽、轉成 `CallbackEvent`），`available?` 改成 true。訂單、狀態機、callback 流程都不用改；測試 G3、G4 驗證「新增 adapter 不需動訂單」。

### 6.2 信用卡
1. `POST /orders`：重算金額；同一個交易內扣名額、建立訂單（pending_payment）、order_discounts、payment；呼叫 `create_payment` → 導向假金流付款頁
2. 假金流頁選「成功／失敗」，可設定 callback 延遲秒數
3. 假金流把瀏覽器導回 `/orders/:public_id`（顯示「付款處理中」），同時由背景 job 以 HTTP POST 呼叫 `/payments/callbacks/fake`（帶簽章）
4. 系統處理 callback（§6.5），訂單轉為 paid 或 failed
5. 訂單頁每 2 秒輪詢，自動顯示完成頁或失敗頁（見下方「訂單頁自動更新」）

**只有驗簽通過的 callback 能改變訂單狀態；瀏覽器導回只負責顯示目前狀態。** 因為瀏覽器導回的網址可以被竄改，也可能因為網路中斷根本沒回來；伺服器對伺服器的 callback 有簽章，才是可信的來源。

**訂單頁自動更新**
| 付款方式 | 做法 | 理由 |
|---|---|---|
| 信用卡 | 每 2 秒用 Turbo morph 重新整理；分頁切到背景（`document.hidden`）時暫停，切回來立刻更新一次 | 結果通常幾秒內就到；沒人在看就不發請求 |
| ATM | 不自動更新，頁面上有「重新整理」按鈕 | 轉帳可能幾天後才發生，一直輪詢只是白白消耗伺服器與手機電量 |

訂單離開待付款後，新頁面沒有 poll controller，輪詢自動停止。

替代做法：用 Turbo Streams（WebSocket）在 callback 處理完時主動推送新狀態，最即時、沒有白跑的請求；代價是每位使用者多佔一條長連線，正式環境要另外準備（Solid Cable 或 Redis）。等待時間只有幾秒的情境，輪詢較簡單，所以本輪不採用。

### 6.3 ATM
建立訂單時 adapter 回傳虛擬帳號與繳費期限 → 訂單頁顯示 → 在假金流 ATM 頁按「模擬已轉帳」→ callback → paid。逾期未付由 rake task 轉為 expired。訂單頁不自動更新（見 §6.2）。

### 6.4 0 元訂單
總額為 0：不建立 payment、不呼叫金流，同一個交易內轉 paid（`payment_method = free`），直接導向完成頁。

### 6.5 Callback 處理（`Payments::ProcessCallback`）
1. 驗證 HMAC-SHA256 簽章（使用 `secure_compare`）。失敗 → 401，不動任何資料
2. 時間戳與現在相差超過 5 分鐘 → 拒絕（防重放）
3. 用 `trade_no` 找 payment。找不到 → 200＋ignored
4. 寫入 `payment_events`。撞到唯一索引 → 200＋duplicate
5. 金額不符 → payment 標為 `needs_review(amount_mismatch)`，回 200
6. 依訂單目前狀態處理：

| 訂單狀態 | 通知 | 處理 |
|---|---|---|
| pending_payment | success | pay；payment → paid |
| pending_payment | failed | fail；payment → failed；釋放名額 |
| paid | 任何 | 忽略並記錄 |
| failed | success | 忽略並記錄 |
| expired / cancelled | success | 訂單不變；payment → `needs_review(late_payment)` |

7. 回 200

回 200 只代表「已收到通知」，讓金流不再重送，不代表系統接受這筆付款。

**同一個通知送兩次、或兩次同時到，會不會重複入帳？** 不會，有兩層保護：
1. `payment_events (provider, event_id)` 唯一索引：第二次寫入就撞到，回 200＋duplicate
2. 狀態轉換本身是條件更新（`WHERE status = 'pending_payment'`），就算是不同 event_id 也只會成功一次

事件寫入和狀態轉換在同一個交易裡，中途失敗會一起回復，金流重送時可以重新處理。簽章含時間戳，超過 5 分鐘拒絕（防重放）；比對用 `secure_compare`，避免時間差攻擊。

### 6.6 需要人工處理的付款（needs_review）
| 原因 | 訂單 | 使用者看到 |
|---|---|---|
| late_payment | 維持 expired／cancelled | 「此訂單已失效，但我們收到了你的付款，將為你辦理退款」 |
| amount_mismatch | 維持 pending_payment，逾期 job 會跳過（錢可能已入帳，不自動釋放名額） | 「付款資訊異常，客服將與你聯繫」 |

### 6.7 逾期取消（`Orders::ExpireOverdue`）
條件：`status = pending_payment AND expires_at < now AND 沒有 needs_review 的付款` → 逐筆 expire。
執行：`bin/rails orders:expire_overdue`（部署在 Heroku 時可用 Scheduler 定期執行）。Demo 用 `ATM_EXPIRE_MINUTES=1` 縮短期限。

### 6.8 假金流
- `/fake_gateway/pay/:trade_no`：信用卡付款頁
- `/fake_gateway/atm/:trade_no`：ATM 模擬轉帳頁
- `/fake_gateway/debug`：重送 callback、送出錯誤簽章、金額不符、先成功再失敗
- 只在 development／test 環境掛載

---

## 7. 路由

| 類型 | 路徑 | 說明 | 快取 |
|---|---|---|---|
| 讀 | `GET /` | 專案列表；輸入方案 ID 前往結帳 | 可 |
| 讀 | `GET /projects/:slug` | 專案頁 | 可 |
| 讀 | `GET /projects/:slug/rewards` | 選擇回饋方案 | 可 |
| 讀 | `GET /rewards/:id/stock` | 剩餘名額 | 短 TTL |
| 寫 | `GET /projects/:slug/checkout?reward=:id` | 結帳頁；沒帶 `reward` 轉回選方案頁 | 否 |
| 寫 | `GET /go?reward_id=` | 首頁輸入方案 ID 後轉址 | 否 |
| 寫 | `POST /checkout/quote` | 即時金額預覽（Turbo Stream） | 否 |
| 寫 | `POST /orders` | 建立訂單並開始付款 | 否 |
| 寫 | `GET /orders/:public_id` | 訂單頁（依狀態顯示不同內容） | 否 |
| 寫 | `POST /orders/:public_id/cancel` | 取消待付款訂單 | 否 |
| 寫 | `POST /payments/callbacks/:provider` | 金流 callback（不檢查 CSRF，改驗簽章） | 否 |

選方案頁與結帳頁用不同路徑，CDN 規則只要寫「`/checkout` 不快取」，不用判斷網址參數。

### 7.1 讀寫分離與快取
熱門專案時，大部分流量都在看同一個專案頁。讀取頁（「可」快取的那幾列）對每個人都長得一樣，所以：
- 不寫 session（沒有 `Set-Cookie`）、不輸出 CSRF token
- 回 `Cache-Control: public, max-age=60, s-maxage=300`：瀏覽器可重用 60 秒，CDN（例如 Cloudflare）可重用 5 分鐘
- Rails 自動加上 `ETag`（內容指紋），內容沒變時回 304

真正打到伺服器的只剩結帳和付款，而名額正確性由資料庫的條件更新保證（§4.5），不依賴快取是否最新。專案頁上的剩餘名額可能是幾分鐘前的，需要即時數字時改呼叫 5 秒 TTL 的 `/rewards/:id/stock`。

**怎麼在 DevTools 觀察**（Network 分頁，先取消勾選「Disable cache」）

| 操作 | 看到的結果 | 意思 |
|---|---|---|
| 60 秒內從別頁點連結回到專案頁 | Status `200`，Size 欄顯示 `(disk cache)` 或 `(memory cache)` | 瀏覽器直接用快取，完全沒有發請求 |
| 按重新整理（⌘R） | Status `304 Not Modified` | 瀏覽器帶 `If-None-Match` 問伺服器「內容變了嗎？」，伺服器只回「沒變」，不傳內容 |
| 強制重新整理（⌘⇧R）或勾了 Disable cache | Status `200`，完整下載 | 瀏覽器刻意不用快取 |

注意：Rails log 在 304 時仍會寫 `Completed 200`，因為 304 是在 controller 之後的 middleware（`Rack::ConditionalGet`）才轉換的。`s-maxage` 是給 CDN 看的，本機沒有 CDN，所以看不到它的效果。

### 7.2 `POST /orders` 參數
```
checkout_token, reward_id, addon_ids[], discount_code, donation, payment_method,
ship_region, ship_city, ship_district, ship_zip, ship_address, recipient_name, recipient_phone,
invoice_type, carrier_code, company_tax_id, company_title
```
| 情況 | 回應 |
|---|---|
| 成功 | 信用卡 → 假金流頁；ATM／0 元 → 訂單頁 |
| `aftee` 或不存在的付款方式 | 422 |
| 名額已滿 | 422，不建立訂單 |
| 欄位驗證失敗（電話 09 開頭共 10 碼；載具 `/` ＋ 7 碼；統編 8 碼） | 422，保留已填資料 |
| 沒選收件地點 | 422「請選擇收件地點」，不建立訂單、不扣名額 |
| `checkout_token` 已存在 | 導向既有訂單 |

### 7.3 Callback 格式
```
POST /payments/callbacks/fake
X-Timestamp: <unix time>
X-Signature: hex(HMAC_SHA256(secret, "#{timestamp}.#{raw_body}"))
{"event_id":"evt_…","trade_no":"FK…","status":"success|failed","amount":"3280","currency":"TWD"}
```

---

## 8. 畫面
- **選方案頁**：方案卡片（標題、贊助價、折數、預定售價、剩餘名額、方案內容、運費標示、預計實現日、選擇按鈕）
- **結帳頁**：左側方案摘要、折扣碼、金額明細；右側付款方式（AFTEE 灰階並標示「尚未開放」）、加碼贊助、收件地點（預設「請選擇收件地點」）、收件地址、收件人、聯絡電話、發票資訊；加購以勾選框呈現；送出按鈕顯示應付金額（例：「確認付款 NT$ 2,780」），隨預覽即時更新；運費未知時只顯示「確認付款」，避免金額看起來比實際少；驗證失敗重新顯示時，錯誤欄位只加紅框與 `aria-invalid`，不另外包一層（Rails 預設會包 `field_with_errors`，會讓格線排版跑掉）
- **Stimulus**：`quote`（欄位變動 300ms 後向伺服器要金額片段）、`address`（縣市 → 鄉鎮市區 → 郵遞區號；收錄台北市、新北市、桃園市、台南市、澎湖縣、金門縣）、`invoice`（個人／公司切換）
- **訂單頁**：依狀態顯示處理中、ATM 繳費資訊、完成、失敗（附「重新結帳」）、已取消、已過期、需人工處理

---

## 9. 程式結構
```
app/models/     Project, Reward, Addon, ShippingRate, DiscountCode, Order, OrderAddon,
                OrderDiscount, Payment, PaymentEvent, OrderTransition
app/services/   checkout/price_calculator.rb
                orders/{create,transition,expire_overdue}.rb
                inventory.rb
                payments/{registry,process_callback,signature}.rb
                payments/adapters/{base,fake_credit_card,fake_atm,aftee}.rb
app/lib/        money.rb
app/controllers/ home, projects, rewards, checkouts, quotes, orders, payments/callbacks, fake_gateway/*
app/jobs/       deliver_fake_callback_job, expire_overdue_orders_job
lib/tasks/      orders.rake
config/         tw_zipcodes.yml
```
Controller 只負責接參數、呼叫 service、決定畫面；業務規則放在 service 與 model。

**查詢原則**：列表頁在 controller 一次載入畫面會用到的關聯（`includes`），SQL 句數不隨列表長度增加（避免 N+1）。
- 選方案頁：方案＋運費＋專案加購
- 結帳頁：專案加購只載入一次，「有沒有加購」和「加購清單」共用同一份

---

## 10. Seed
專案《山城慢遊》手繪地圖書（`/projects/mountain-map`）：

| 方案 ID | 方案 | 贊助價 | 名額 | 用途 |
|---|---|---|---|---|
| 1 | 收藏套組 | 2980（預定售價 3725，顯示 8 折） | 200／已佔 190 | 主要流程、剩餘名額 |
| 2 | 早鳥單本 | 800 | 100／0 | 搭配 `FREE800` 產生 0 元訂單 |
| 3 | 最後一席 | 1200 | 1／0 | 搶最後一個名額 |
| 4 | 明信片組 | 500 | 300／0 | 搭配 `FREE800`：折扣不超過方案金額，只折 500 |

- 加購：加購小物 300、書籤組 100、帆布袋 250
- 折扣碼：`SAVE500`（折 500）、`FREE800`（折 800）、`EXPIRED`（已過期）
- 運費：本島 0；離島 100（有加購再加 30）；海外 300（有加購再加 50）
- 另有專案「島嶼桌遊 Demo」（方案 ID 5、折扣碼 `GAME100`），用來展示折扣碼與加購不能跨專案使用

---

## 11. 擴充點
| 需求 | 目前的結構 | 擴充方式 |
|---|---|---|
| 真實金流、AFTEE | Adapter 介面與 Registry | 新增 adapter 類別（§6.1） |
| 專案到期結算、失敗退款 | `funding_goal`、`ends_at`、轉換表、`refund` 介面、`needs_review` | 新增 refunded 狀態與結算排程（§4.2） |
| 多幣別／海外站 | decimal＋currency、`Money::PRECISION`、依地區的運費 | 匯率與各站設定（§2.2） |
| 一張訂單同時使用多張折扣碼 | 訂單用了哪些碼記在 `order_discounts`（一碼一列），而不是 orders 上的單一欄位；目前以 `order_id` 唯一索引限制一單一碼 | 移除唯一索引，並在計算器加上多碼的疊加規則 |
| 固定金額以外的折扣（例：打折、滿額折） | 每筆折扣在 `order_discounts` 都存成「折了多少錢」，與折扣怎麼算無關 | `discount_codes` 新增類型欄位（例：`fixed`／`percent`），計算器依類型算出金額；訂單與明細表不用改（§5） |
| 方案限定加購 | — | 新增 `reward_addons`（方案 × 加購）對照表，列出每個方案可加購的項目 |
| 折扣碼使用次數限制 | — | 新增 `usage_limit／used_count`，以與名額相同的條件更新扣減 |
| 全平台折扣碼 | — | `discount_codes.project_id` 改為可為空 |
| 加購庫存 | — | `addons` 增加名額欄位，扣減方式同方案（§4.5） |
| 商品頁快取 | 讀寫路徑分離 | Cloudflare 快取規則；剩餘名額由短 TTL 端點提供（§7.1） |
