import { Controller } from "@hotwired/stimulus"

// 信用卡訂單待付款時，每隔幾秒重新整理頁面，等金流 callback 改變訂單狀態。
//
// 重新整理用 Turbo 的 morph：只更新有變的部分，這個元素本身不會被換掉，
// 所以用 setInterval 持續輪詢。訂單離開待付款後，新頁面的這個元素不再有
// data-controller="poll"，Stimulus 會呼叫 disconnect()，輪詢就停止。
//
// 使用者切到別的分頁、或手機鎖屏時（document.hidden），先暫停輪詢，
// 沒人在看就不浪費請求；切回來時立刻更新一次，再繼續輪詢。
export default class extends Controller {
  static values = { interval: { type: Number, default: 2000 } }

  connect() {
    // 先把函式存起來，disconnect 時才能用同一個函式移除監聽
    this.onVisibilityChange = () => (document.hidden ? this.stop() : this.resume())
    document.addEventListener("visibilitychange", this.onVisibilityChange)
    if (!document.hidden) this.start()
  }

  disconnect() {
    this.stop()
    document.removeEventListener("visibilitychange", this.onVisibilityChange)
  }

  start() {
    this.stop() // 避免重複開兩個計時器
    this.timer = setInterval(() => this.refresh(), this.intervalValue)
  }

  stop() {
    clearInterval(this.timer)
    this.timer = null
  }

  // 從背景切回來：狀態可能早就變了，先馬上更新一次
  resume() {
    this.refresh()
    this.start()
  }

  refresh() {
    Turbo.visit(window.location.href, { action: "replace" })
  }
}
