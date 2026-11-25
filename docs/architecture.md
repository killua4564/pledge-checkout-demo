# 架構說明

## 一句話
Rails monolith，伺服器端渲染（ERB ＋ Hotwire），SQLite。業務規則集中在 `app/services`，controller 只負責接參數、呼叫 service、決定畫面。

## 全貌

```
                 ┌──────────────── 讀（可快取，CDN 擋在前面）────────────────┐
瀏覽器 ──GET──▶  │ /                 /projects/:slug    /projects/:slug/rewards（選方案）   │
                 │ /rewards/:id/stock（剩餘名額，短 TTL）                                   │
                 └──────────────────────────────────────────────────────────────────┘
                 ┌──────────────── 寫（不可快取）──────────────────────────────────────┐
瀏覽器 ──────▶   │ /projects/:slug/checkout?reward=   POST /checkout/quote   POST /orders │
                 │ GET /orders/:public_id     POST /orders/:public_id/cancel             │
                 └──────────────────────────────────────────────────────────────────┘
金流 ──POST──▶   /payments/callbacks/:provider（驗簽章，不驗 CSRF）
排程 ──────▶     bin/rails orders:expire_overdue
```

## 主要元件

| 元件 | 責任 |
|---|---|
| `Checkout::PriceCalculator` | 唯一算錢處。預覽與下單共用；前端不送金額 |
| `CheckoutForm` | 收件、電話、發票、付款方式等欄位驗證 |
| `Orders::Create` | 防重複送出 → 驗證 → 重算 → 交易內扣名額＋建單 → 交易後建立付款 |
| `Inventory` | 原子化條件更新扣／還名額 |
| `Order::TRANSITIONS` ＋ `Orders::Transition` | 狀態機：轉換表＋條件更新；失效時釋放名額；寫稽核紀錄 |
| `Payments::Registry` ＋ `Payments::Adapters::*` | 付款方式對應 adapter（假信用卡、假 ATM、AFTEE 未開放） |
| `Payments::ProcessCallback` | 驗簽 → 找付款 → 冪等寫入事件 → 核對金額 → 依訂單狀態轉換 |
| `Orders::ExpireOverdue` | 逾期未付轉 expired，跳過需人工處理的付款 |
| `PublicCacheable` | 讀取頁面不寫 session、不輸出 CSRF、送 `Cache-Control: public` |

## 一筆訂單的生命週期

```
結帳頁送出
  └─ Orders::Create
       ├─ 交易：Inventory.reserve! → Order(pending_payment) → order_addons / order_discounts
       │        （0 元訂單：同一交易內 Transition :pay → 完成頁）
       └─ adapter.create_payment → Payment(pending)
            ├─ 信用卡：導向假金流頁 → 使用者選成功／失敗
            └─ ATM：訂單頁顯示虛擬帳號 → 假金流「模擬已轉帳」
                      │
                      ▼  DeliverFakeCallbackJob（背景，HTTP POST + HMAC 簽章）
              /payments/callbacks/fake → Payments::ProcessCallback
                      ├─ success → Transition :pay   → paid
                      └─ failed  → Transition :fail  → failed（釋放名額）

沒付款：orders:expire_overdue → Transition :expire → expired（釋放名額）
使用者取消：Transition :cancel → cancelled（釋放名額）
失效後才付款：訂單不變，Payment → needs_review(late_payment)
```

訂單頁待付款時每 2 秒重新整理（Turbo morph），callback 到了畫面自動更新。

## 資料表

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

保護資料正確性的資料庫約束：

| 約束 | 防止什麼 |
|---|---|
| `rewards` CHECK `0 <= quota_taken <= quota_total` | 超賣（程式錯了也擋得住） |
| `orders.checkout_token` 唯一 | 重複送出建立兩張單 |
| `payment_events (provider, event_id)` 唯一 | 同一則 callback 被處理兩次 |
| `payments (provider, provider_trade_no)` 唯一 | 交易編號重複 |
| `order_discounts.order_id` 唯一 | 一單多碼（目前不開放） |
| `order_addons (order_id, addon_id)` 唯一 | 同一加購買兩個 |

## 部署到 Heroku 時要換的東西

| 本機 | Heroku |
|---|---|
| SQLite | Postgres（程式不用改；條件更新在 Postgres 一樣是原子的） |
| ActiveJob `:async` | Solid Queue 或 Sidekiq（job 程式不用改） |
| 手動 `bin/rails orders:expire_overdue` | Heroku Scheduler 每 10 分鐘執行 |
| 假金流 | 真實金流 adapter（假金流路由只在 development／test 存在） |
| `FAKE_GATEWAY_SECRET` 預設值 | 用 config vars 設定真正的密鑰 |
