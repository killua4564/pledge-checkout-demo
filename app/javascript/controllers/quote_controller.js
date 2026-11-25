import { Controller } from "@hotwired/stimulus"

// 結帳頁的「即時金額更新」。
//
// 重點：前端不算錢。欄位一變動，就把整張表單目前的選擇送到 /checkout/quote，
// 由伺服器用 Checkout::PriceCalculator 算好，回傳新的金額區塊（Turbo Stream）直接替換。
// 等使用者停手 300 毫秒才送，避免每打一個字就送一次。
export default class extends Controller {
  static values = { url: String }

  refresh(event) {
    // 只有會影響金額的欄位才需要重算（打收件人姓名不用）
    const name = event.target.name || ""
    const affectsPrice = ["discount_code", "donation", "ship_region", "addon_ids"].some((key) => name.includes(key))
    if (!affectsPrice) return

    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.fetchQuote(), 300)
  }

  async fetchQuote() {
    const response = await fetch(this.urlValue, {
      method: "POST",
      headers: {
        Accept: "text/vnd.turbo-stream.html",
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content,
      },
      body: new FormData(this.element),
    })
    if (response.ok) {
      Turbo.renderStreamMessage(await response.text())
    }
  }
}
