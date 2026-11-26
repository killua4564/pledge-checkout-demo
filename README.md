# pledge-checkout-demo：群眾集資贊助結帳

用 Rails 實作的「贊助結帳」簡化版：選回饋方案 → 填資料 → 信用卡／ATM 付款（假金流）→ 訂單結果。
第三方金流以本機的「假金流」頁面取代，並透過有簽章的非同步 callback 通知系統。

| 文件 | 內容 |
|---|---|
| [docs/spec.md](docs/spec.md) | 規格：資料表、狀態機、金額規則、付款流程、路由、快取；各章附「擴充」做法 |
| [docs/test-plan.md](docs/test-plan.md) | 測項清單（編號對應測試名稱） |
| [docs/architecture.md](docs/architecture.md) | 一頁架構說明 |
| [docs/decisions.md](docs/decisions.md) | 設計決策與取捨、哪裡適合加快取 |

---

## 需要的環境

- Ruby 3.3（`.ruby-version` 指定 3.3.14）
- SQLite 3
- 不需要 Node、Redis 或任何外部服務
- 畫面自動測試需要 Google Chrome（第一次執行時 Selenium 會自動下載 chromedriver）

## 安裝與啟動

```bash
bin/setup --skip-server
```

這一步會安裝套件、建立資料庫並載入 Demo 資料。接著啟動：

```bash
bin/dev
```

`bin/dev` 會同時啟動網站和 Tailwind CSS 編譯。打開 http://localhost:3000

重置 Demo 資料（清空訂單，名額回到初始狀態）：

```bash
bin/rails db:seed
```

## 測試

```bash
bin/rails test
```

```bash
bin/rails test:system
```

第一個是單元與整合測試，第二個是畫面自動測試（會開一個看不見的 Chrome）。

## 環境變數

| 變數 | 預設 | 用途 |
|---|---|---|
| `ATM_EXPIRE_MINUTES` | 4320（3 天） | ATM 繳費期限；Demo 可設 1 |
| `CARD_EXPIRE_MINUTES` | 15 | 信用卡付款期限 |
| `FAKE_GATEWAY_SECRET` | 開發用預設值 | 假金流與系統之間的簽章密鑰（正式環境必填） |
| `APP_BASE_URL` | `http://localhost:3000` | 假金流把 callback 送到哪裡 |

---

## Demo 步驟

Demo 資料（`db/seeds.rb`）：

| 方案 ID | 方案 | 價格 | 名額 | 用途 |
|---|---|---|---|---|
| 1 | 收藏套組 | 2,980 | 剩 10 | 主要流程 |
| 2 | 早鳥單本 | 800 | 剩 100 | 搭配 `FREE800` 產生 0 元訂單 |
| 3 | 最後一席 | 1,200 | 剩 1 | 搶最後一個名額 |
| 4 | 明信片組 | 500 | 剩 300 | 搭配 `FREE800`：折扣不超過方案金額，只折 500 |
| 5 | 島嶼桌遊 基本版 | 1,200 | 剩 288 | 另一個專案（跨專案限制） |

折扣碼：`SAVE500`（折 500）、`FREE800`（折 800）、`EXPIRED`（已過期）、`GAME100`（只能用在桌遊專案）

### 1. 信用卡付款成功
1. 首頁輸入方案 ID `1`，按「前往結帳」
2. 勾選「加購小物」→ 總金額變 NT$ 3,280；輸入折扣碼 `SAVE500` → 變 NT$ 2,780
3. 選收件地點（預設是「請選擇」，選了才會算運費）、縣市、鄉鎮市區（郵遞區號自動帶入），填地址、收件人、電話，按「確認付款」
4. 進入假金流頁，可選「callback 延遲 5 秒」，按「付款成功」
5. 回到訂單頁先顯示「付款處理中」，callback 到了自動變成「贊助成功！」

### 2. 信用卡付款失敗
同上，在假金流頁按「付款失敗」→ 失敗頁，名額回補，可「重新結帳」。

### 3. ATM 轉帳
1. 結帳時選「ATM 轉帳」→ 訂單頁顯示虛擬帳號與繳費期限
2. 按「前往假金流：模擬 ATM 轉帳」→「模擬已轉帳」→ 完成頁

### 4. ATM 逾期
1. 用短期限啟動伺服器：

   ```bash
   ATM_EXPIRE_MINUTES=1 bin/dev
   ```

2. 建立一張 ATM 訂單，等 1 分鐘後執行逾期處理（也可以在「假金流 Demo 工具」頁按按鈕）：

   ```bash
   bin/rails orders:expire_overdue
   ```

3. 訂單頁顯示「訂單已過期」，名額回補
4. 這時再去假金流頁「模擬已轉帳」→ 訂單維持已過期，顯示「將為你辦理退款」

### 5. 異常通知（右上角「假金流 Demo 工具」）
- **重送最後一次**：同一個 event_id 再送一次 → 結果 `duplicate`，訂單只處理一次
- **錯誤簽章** → `rejected_signature`，訂單不變
- **金額不符** → `rejected_amount`，付款標記為需要人工處理
- **先成功再失敗** → 訂單維持已付款

### 6. 其他
- 方案 ID `3`「最後一席」：第一張訂單建立後，第二個人結帳會看到「名額已經被搶完」
- 方案 ID `2` + 折扣碼 `FREE800` → 0 元訂單，直接完成
- 在結帳頁用開發者工具把 AFTEE 的 `disabled` 拿掉再送出 → 伺服器仍拒絕「尚未開放」

## 程式碼導覽

| 想看什麼 | 檔案 |
|---|---|
| 所有資料表 | `db/migrate/20261125000001_create_checkout_schema.rb`（之後的索引調整在同資料夾的新 migration；完整現況看 `db/schema.rb`） |
| 金額計算 | `app/services/checkout/price_calculator.rb` |
| 建立訂單 | `app/services/orders/create.rb` |
| 狀態機 | `app/models/order.rb`（轉換表）、`app/services/orders/transition.rb` |
| 名額扣減 | `app/services/inventory.rb` |
| callback 處理 | `app/services/payments/process_callback.rb`、`app/services/payments/signature.rb` |
| 金流 adapter | `app/services/payments/registry.rb`、`app/services/payments/adapters/` |
| 逾期處理 | `app/services/orders/expire_overdue.rb`、`lib/tasks/orders.rake` |
| 讀寫分離與快取標頭 | `config/routes.rb`、`app/controllers/concerns/public_cacheable.rb` |
