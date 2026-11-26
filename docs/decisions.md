# 設計決策

格式：**決定**｜考慮過的替代方案｜為什麼這樣選

## 架構與技術

| 決定 | 替代方案 | 理由 |
|---|---|---|
| Rails monolith、ERB 伺服器渲染 | 前後端分離（API + SPA） | 題目規模小；與目標團隊（Rails monolith）一致；少一層 API 契約要維護 |
| Hotwire（Turbo + Stimulus）只做必要互動 | React／Vue | 互動只有即時金額、地址連動、發票切換、輪詢；不需要前端狀態管理 |
| importmap、tailwindcss-rails | Node 工具鏈 | clone 下來不用裝 Node 就能跑 |
| SQLite | Postgres | 不需要外部服務；所有並行保護都用標準 SQL 條件更新，換 Postgres 不用改程式 |
| ActiveJob `:async` | Solid Queue／Sidekiq | 不需要 Redis；介面相同，部署時換 adapter 即可 |
| 業務邏輯放 `app/services` 的小類別 | 全部寫在 model（fat model） | 每個流程一個檔案，好找、好擴充，測試也好寫 |
| Minitest ＋ 系統測試 | RSpec | Rails 內建，少一個依賴 |

## 金額

| 決定 | 替代方案 | 理由 |
|---|---|---|
| 金額由伺服器 `PriceCalculator` 計算，前端只送選擇 | 前端算好送總額、後端驗證 | 只有一個算錢的地方，預覽和下單不可能不一致；strong params 直接丟掉前端送的金額欄位 |
| 即時預覽由伺服器回傳 HTML 片段（Turbo Stream） | 前端 JS 自己算 | 避免前後端各寫一套規則 |
| `decimal(12,2)` ＋ `currency` | 整數存最小單位（分）；float | float 有誤差，不可用。decimal 和整數都精確，decimal 較好讀；金流格式轉換放在 adapter（`gateway_amount`） |
| 依幣別小數位數捨入（`Money::PRECISION`） | 寫死 TWD | 多幣別、海外站的擴充點 |
| 折扣只折方案金額，上限為方案金額 | 折總額 | 折扣碼顯示在「主選項金額」旁，語意上折的是方案；確保總額不為負 |
| 總額 0 元：不經金流直接轉 paid | 禁止 0 元；最低收 1 元 | 金流多半不收 0 元交易；仍走狀態機，留下轉換紀錄 |
| 金額欄位存快照（訂單、加購、折扣） | 每次從商品即時算 | 商品改價不影響已成立的訂單 |

## 折扣碼與加購

| 決定 | 替代方案 | 理由 |
|---|---|---|
| 折扣碼屬於專案、只有固定金額 | 全站碼、百分比、滿額門檻、每人限用 | 折扣碼由提案團隊發行，例如「再折 500 元」；其他類型列為擴充點（spec §5） |
| `order_discounts` 一碼一列，以唯一索引限制一單一碼 | `orders.discount_code_id` 單一欄位 | 日後一單多碼只要拿掉索引；明細只記「折了多少」，與折扣怎麼算無關 |
| 加購屬於專案、每項最多 1 個 | 每項可選數量；依方案限定 | 最常見的用法；方案限定日後用 `reward_addons` 對照表 |
| 運費跟著方案、依地區查表 | 跟著專案 | 不同方案的包裹大小不同，運費自然不同；方案卡片可標示「臺灣本島免運」 |

## 訂單與狀態機

| 決定 | 替代方案 | 理由 |
|---|---|---|
| 自己寫狀態機（轉換表 ＋ 條件更新） | AASM gem | AASM 預設先讀後寫，並行要靠 `SELECT … FOR UPDATE`，SQLite 不支援；手寫版一句 SQL 完成檢查＋修改，也好解釋 |
| 所有轉換走 `Orders::Transition` 一個入口 | 各處自己改 status | callback、逾期、取消、0 元訂單共用同一套規則與稽核 |
| 狀態決定是否佔名額，不另存旗標 | `quota_reserved` 欄位 | 條件更新保證只離開待付款一次，名額只會釋放一次；少一個會不一致的欄位 |
| `expired`（系統逾期）與 `cancelled`（使用者取消）分開 | 都叫 cancelled | 報表與客服需要區分原因 |
| `public_id` 用 UUID | 流水號 id | 沒有登入，網址不能被猜到 |
| `checkout_token` 與 `public_id` 分開 | 共用一個 UUID | token 代表「這一次送出」、每次進結帳頁重新產生；共用的話，失敗後按上一頁重送會回到舊訂單 |
| 付款建立放在訂單交易之後 | 放在交易內 | 真實金流要打外部 API，不該讓資料庫交易一直開著；失敗就把訂單轉 failed 並釋放名額 |

## 名額

| 決定 | 替代方案 | 理由 |
|---|---|---|
| `UPDATE … WHERE quota_taken < quota_total` 原子化扣名額 | 先查剩餘再寫入；應用程式層加鎖；Redis 計數 | 先查再寫會超賣；鎖或 Redis 增加複雜度與外部依賴 |
| 資料庫 CHECK 約束 | 只靠程式 | 最後一道防線 |
| 下單（待付款）就佔名額，失效時釋放 | 付款成功才扣 | 避免「付了錢卻沒名額」；代價是放棄付款的人會暫時佔位，所以信用卡 15 分鐘、ATM 3 天逾期 |
| 方案沒有共用庫存（bundle 算一份） | `inventory_items` 共用庫存 | 募資平台以「份」計，不是快速出貨的電商 |

## 付款與 callback

| 決定 | 替代方案 | 理由 |
|---|---|---|
| 付款方式用 adapter ＋ Registry | 在 controller 裡 if/else | 換真實金流、開放 AFTEE 只新增一個類別 |
| 只有驗簽通過的 callback 能改訂單狀態 | 依瀏覽器導回的參數判斷 | 瀏覽器導回可以被竄改或中斷 |
| HMAC-SHA256（時間戳＋內文）＋ `secure_compare` ＋ 5 分鐘時效 | 只驗 IP；不驗 | 防偽造、防竄改、防重放；固定時間比對避免被逐字猜出簽章 |
| `payment_events (provider, event_id)` 唯一索引做冪等 | 先查有沒有處理過再處理 | 先查再寫在並行時會重複處理；唯一索引由資料庫保證 |
| 重複通知、找不到交易也回 200 | 回 4xx | 非 200 金流會一直重送；200 只代表「收到了」 |
| 事件寫入與狀態轉換在同一個交易 | 分開 | 中途失敗會整個回復，金流重送時可以重新處理 |
| 訂單失效後才付款：訂單不復活，付款標 `needs_review(late_payment)` | 重新扣名額讓訂單復活 | 名額可能已被別人買走；退款是擴充點 |
| 金額不符：訂單維持待付款、付款標 `needs_review`，逾期處理跳過 | 直接轉失敗 | 錢可能已扣，不能自動釋放名額，交給人工 |
| 逾期處理的「排除需人工處理」條件併進轉換的 `UPDATE` | 先查名單再逐筆轉換 | 先查再做之間可能剛好收到金額不符的通知；同一句 SQL 沒有空檔 |
| `payments` 加部分索引（只收 `needs_review`） | 整欄 `status` 索引；不加 | 只需要找極少數的異常付款；部分索引小、寫入幾乎不受影響 |
| 已 paid 收到 failed、已 failed 收到 success：忽略並記錄 | 以最後一則為準 | 終點狀態不能被後到的通知推翻 |
| 假金流用真的 HTTP 打自己的 callback 網址 | 程式內直接呼叫 | 貼近真實；測試環境改用程式內呼叫（沒有固定網址的伺服器） |
| 逾期處理用 rake task（包成 job） | 常駐排程器 | 簡單；Heroku Scheduler 可直接執行 |

## 讀寫分離與快取

| 決定 | 替代方案 | 理由 |
|---|---|---|
| 讀取頁（首頁、專案頁、選方案頁）不寫 session、不輸出 CSRF、送 `Cache-Control: public, max-age=60, s-maxage=300` | 所有頁面一樣 | 熱門專案流量集中在這幾頁；回應中有 Set-Cookie 或個人化 token 時 CDN 無法共用快取 |
| 首頁錯誤訊息用網址參數，不用 flash | flash | flash 需要 session cookie，會讓首頁無法快取 |
| 剩餘名額另開 `/rewards/:id/stock`（TTL 5 秒） | 名額寫在大頁面裡、頁面不快取 | 大頁面長快取、小數字短快取，兩者分開 |
| 選方案頁 `/projects/:slug/rewards` 與結帳頁 `/projects/:slug/checkout?reward=` 分成兩個路徑 | 同一路徑以參數區分 | CDN 規則只要依路徑判斷，不會因為參數寫錯而把結帳頁快取起來 |

### 哪裡適合加快取（不在本專案實作）

| 位置 | 做法 | 注意 |
|---|---|---|
| Cloudflare：專案頁 `/projects/:slug` | Cache Rule 快取 HTML（依 `s-maxage`）；專案內容更新時用 Cache Tag 或 URL purge | 99% 流量的熱門頁，效果最大 |
| Cloudflare：選方案頁 `/projects/:slug/rewards` | 同專案頁 | 結帳頁在另一個路徑 `/checkout`，規則設為 bypass |
| 剩餘名額 | 可快取幾秒；或由前端每隔幾秒向 `/rewards/:id/stock` 更新 | 數字略舊沒關係，真正下單時由原子化扣名額把關 |
| Rails fragment cache | 方案卡片、專案介紹以 `cache reward` 快取（Solid Cache 或 Redis） | CDN 沒命中時減輕資料庫負擔 |
| 不可快取 | 結帳頁、`/checkout/quote`、`/orders/*`、`/payments/callbacks/*` | 個人化或寫入 |
| 海外站 | 各站自己的 Cloudflare 設定，快取鍵需包含網域；共用後端以 `currency`／站台設定區分 | 不同站同一路徑內容不同，不能互相命中 |

## 擴充點（只留結構，沒有實作）

| 需求 | 目前的結構 | 擴充方式 |
|---|---|---|
| 真實金流、AFTEE | Adapter 介面、Registry | 新增 adapter 類別，Registry 加一行 |
| 專案到期結算、失敗退款 | `projects.funding_goal／ends_at`、轉換表、`Adapter#refund`、`needs_review` | 轉換表加 `refund: paid → refunded`；結算排程逐筆呼叫 `refund` |
| 多幣別／海外站 | decimal ＋ currency、`Money::PRECISION`、依地區運費 | 匯率、各站設定可用的 adapter 與幣別 |
| 一單多碼、百分比折扣 | `order_discounts` 明細表 | 拿掉唯一索引；`discount_codes` 加類型欄位 |
| 折扣碼使用次數限制 | — | `usage_limit／used_count`，扣法同名額 |
| 全平台折扣碼 | — | `discount_codes.project_id` 改為可為空 |
| 方案限定加購、加購庫存 | — | `reward_addons` 對照表；`addons` 加名額欄位 |
