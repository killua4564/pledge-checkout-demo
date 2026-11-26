# CLAUDE.md

群眾募資平台「贊助結帳」Demo：選回饋方案 → 結帳（加購、加碼、折扣碼、運費）→ 信用卡／ATM 付款（假金流＋有簽章的非同步 callback）→ 訂單結果。

## 先讀這些文件（規格以文件為準）
| 文件 | 什麼時候看 |
|---|---|
| `docs/spec.md` | 任何功能改動前。資料表、狀態機、金額規則、付款流程、路由、快取；各章結尾的「擴充」段落寫了日後加功能的做法 |
| `docs/test-plan.md` | 測項清單，編號（A1、D2…）對應測試名稱 |
| `docs/decisions.md` | 每個設計決定的替代方案與取捨 |
| `docs/architecture.md` | 一頁架構總覽 |
| `README.md` | 安裝、啟動、Demo 步驟 |

## 加功能的流程（請照順序，不要跳步）
1. **排查**：讀 `docs/spec.md`，列出這個功能會動到哪些章節、資料表、程式檔案，以及和現有規則**有沒有邏輯衝突**（例如金額計算順序、狀態轉換、名額釋放、冪等）。
2. **討論**：把影響範圍、衝突與可選做法（含取捨）用白話告訴使用者，**等使用者確認結論**。這一步不改任何檔案。
3. **改文件**：更新 `docs/spec.md`（必要時 `docs/decisions.md`），並在 `docs/test-plan.md` 加上新測項編號。
4. **先寫測試**，再改程式。
5. **自我檢查**：寫完程式後，對照下方「資料庫檢查清單」逐項看過，有發現就補測試再修。
6. **驗證**：跑全部測試；能在畫面上看到的改動，啟動伺服器實際在瀏覽器操作一次。
7. 回報改了什麼、哪些還沒驗證；**使用者同意後才 commit**。

## 資料庫檢查清單（排查與自我檢查時都要看）
新增或修改任何查詢、寫入時逐項確認；在「排查」階段就要把會碰到的項目列出來討論，不要等寫完才發現。

| 檢查 | 怎麼確認 | 做法 |
|---|---|---|
| **Index**：新的查詢條件、排序、子查詢有沒有用到索引？ | `EXPLAIN QUERY PLAN`；出現 `SCAN 表名`（後面沒接 `USING INDEX`）＝整張表掃描 | 加索引要另開新的 migration，不改舊的；只查少數幾筆（例如某個狀態）時用部分索引。也要想寫入成本：小表或不會變大的表不用加 |
| **N+1**：列表或迴圈裡有沒有存取關聯（`reward.shipping_rates`、`order.payments`…）？ | 在整合測試裡計算 SQL 句數，資料變多時句數不能跟著變多（參考 H6） | 在 controller 用 `includes` 一次載入；同一份資料（例如「有沒有加購」和「加購清單」）只查一次 |
| **Race condition**：有沒有「先查，再依結果寫」？ | 想像兩個請求同時進來、或在查和寫之間插入另一個請求 | 檢查和動作放在同一句 SQL（條件更新 `UPDATE … WHERE`），或用唯一索引擋重複；不要先讀狀態再 `update!` |
| **終點狀態**：已完成的資料（例如 paid）會不會被後到的事件改掉？ | 列出每個狀態可能收到的事件（含重複、順序顛倒、異常通知） | 終點狀態只記錄、不改；改狀態一律帶條件 |
| **條件合併**：要把兩個查詢條件合在一起時 | 印出 `to_sql` 看兩邊條件是否都還在 | 用 `and`，不要用 `merge`：`merge` 遇到同一個欄位會用後者覆蓋前者（曾因此讓 UPDATE 一次改到整批訂單） |

## Commit 規則
- 在 `main` 上 commit；**不要 push**，使用者看過後自己 push。
- **一件事一個 commit，可以拆成多個**：例如「功能本身（程式＋測試＋對應的 spec）」和「只改文件的擴充說明」分開。判斷方式：每個 commit 單獨看都說得清楚「做了什麼、為什麼」。
- 同一個功能的程式、測試、spec 放在同一個 commit，讓人看一個 commit 就知道規則和實作是一致的。
- 訊息用繁體中文：第一行是一句摘要，空一行後條列重點與原因。
- 不要 commit `private/`（個人筆記，已在本機排除）、`.claude/`、`config/master.key`、資料庫檔。

## 核心規則（改程式時不能破壞）
- **金額只在伺服器算**：`Checkout::PriceCalculator` 是唯一算錢的地方，預覽與下單共用；前端只送「選了什麼」。
- **名額用條件更新扣**：`Inventory` 用 `UPDATE … WHERE quota_taken < quota_total`，不要改成先查再寫。
- **狀態只能經由 `Orders::Transition` 改**：轉換表在 `Order::TRANSITIONS`，條件更新保證只轉一次；失效狀態會釋放名額。需要額外條件時用 `guard:` 併進同一句 UPDATE（例如逾期處理排除需人工處理的付款）。
- **已付款的付款不再改狀態**：`Payment#flag_for_review!` 是條件更新，`paid` 不會被後到的異常通知改成 `needs_review`。
- **只有驗簽通過的 callback 能改付款結果**：`Payments::ProcessCallback`；`payment_events (provider, event_id)` 唯一索引負責冪等。
- **付款方式一律透過 adapter**：`Payments::Registry` ＋ `app/services/payments/adapters/*`，訂單流程不認識具體金流。
- **讀寫分離**：讀取頁用 `PublicCacheable`（不寫 session、不輸出 CSRF、可公開快取）；結帳與訂單頁不可快取。

## 程式位置
```
app/services/checkout/price_calculator.rb   金額計算
app/services/orders/{create,transition,expire_overdue}.rb
app/services/inventory.rb                   名額扣減與釋放
app/services/payments/                      registry、adapters、callback 處理、簽章、假金流通知
app/models/order.rb                         狀態與轉換表
app/models/checkout_form.rb                 結帳欄位驗證
app/controllers/                            只接參數、呼叫 service、決定畫面
app/javascript/controllers/                 Stimulus：quote（即時金額）、address、invoice、poll
db/migrate/                                 第一個 migration 定義全部資料表；之後的調整（例如加索引）另開新的 migration
db/seeds.rb                                 Demo 資料（方案 ID 1～5）
```

## 常用指令
本機 Ruby 由 rbenv 管理；在非互動 shell 執行前先載入 rbenv，並設定 UTF-8 以免中文輸出出錯：

```bash
export LANG=en_US.UTF-8; eval "$(rbenv init - bash)"
```

| 做什麼 | 指令 |
|---|---|
| 啟動（ATM 期限縮成 1 分鐘方便 Demo） | `ATM_EXPIRE_MINUTES=1 bin/dev`，開 http://localhost:3000 |
| 重置 Demo 資料 | `bin/rails db:seed` |
| 單元與整合測試 | `bin/rails test` |
| 畫面測試（無頭 Chrome） | `bin/rails test:system` |
| 逾期處理 | `bin/rails orders:expire_overdue` |
| 假金流 Demo 工具 | http://localhost:3000/fake_gateway/debug |

## 寫作慣例
- 畫面文案、文件、程式註解都用繁體中文；註解寫「為什麼」，讓不熟程式的人也看得懂。
- 改了資料表要同步更新 `docs/spec.md` §3；改了路由要同步更新 §7。
