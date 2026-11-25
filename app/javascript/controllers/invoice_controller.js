import { Controller } from "@hotwired/stimulus"

// 發票類型切換：個人發票顯示手機載具欄位，公司發票顯示統編與抬頭欄位。
export default class extends Controller {
  static targets = ["personal", "company"]

  connect() {
    this.toggle()
  }

  toggle() {
    const checked = this.element.querySelector("input[name='checkout[invoice_type]']:checked")
    const isCompany = checked?.value === "company"
    this.personalTarget.hidden = isCompany
    this.companyTarget.hidden = !isCompany
  }
}
