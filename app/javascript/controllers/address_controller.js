import { Controller } from "@hotwired/stimulus"

// 收件地址連動：收件地點 → 縣市 → 鄉鎮市區 → 郵遞區號（spec §3.4、§8）。
// - 縣市只列出所選收件地點的：選離島只看到澎湖、金門；選本島只看到本島縣市。
//   運費跟著收件地點走，選「本島」卻填金門會少收運費，所以從選項上就避免選錯（伺服器也會再擋一次）。
// - 切換收件地點時清空縣市、鄉鎮市區、郵遞區號：它們都跟地點綁在一起，舊的值留著會變成矛盾的地址
//   （例如先選金門、再改海外，金門其實還在被隱藏的欄位裡）。地址是使用者自己打的字，保留讓他自己改。
// - 寄海外時隱藏縣市與鄉鎮市區。
export default class extends Controller {
  static targets = ["region", "city", "district", "zip", "taiwanOnly"]
  static values = {
    zipcodes: Object, // { "台北市": { "中正區": "100", ... }, ... }
    cities: Object,   // { "tw_main": ["台北市", ...], "tw_island": ["澎湖縣", "金門縣"] }
  }

  connect() {
    // 剛載入頁面（包含驗證失敗重新顯示）：只調整顯示，不清空使用者已經選好的值
    this.toggleTaiwanFields()
  }

  // 使用者切換收件地點
  regionChanged() {
    this.toggleTaiwanFields()
    this.fillCities()
    this.fillDistricts()
    this.zipTarget.value = ""
  }

  cityChanged() {
    this.fillDistricts()
    this.zipTarget.value = ""
  }

  districtChanged() {
    const districts = this.zipcodesValue[this.cityTarget.value] || {}
    this.zipTarget.value = districts[this.districtTarget.value] || ""
  }

  // ── 以下是共用的小工具 ──

  toggleTaiwanFields() {
    this.taiwanOnlyTarget.hidden = !this.regionTarget.value.startsWith("tw_")
  }

  // 依目前的收件地點重建縣市選項（清空已選的縣市）
  fillCities() {
    const cities = this.citiesValue[this.regionTarget.value] || []
    this.replaceOptions(this.cityTarget, "請選擇縣市", cities)
  }

  // 依目前的縣市重建鄉鎮市區選項（清空已選的區）
  fillDistricts() {
    const districts = Object.keys(this.zipcodesValue[this.cityTarget.value] || {})
    this.replaceOptions(this.districtTarget, "請選擇鄉鎮市區", districts)
  }

  replaceOptions(select, placeholder, names) {
    select.innerHTML = ""
    select.add(new Option(placeholder, ""))
    names.forEach((name) => select.add(new Option(name, name)))
  }
}
