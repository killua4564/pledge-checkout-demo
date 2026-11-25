import { Controller } from "@hotwired/stimulus"

// 收件地址連動：選縣市 → 列出該縣市的鄉鎮市區 → 選了鄉鎮市區自動帶出郵遞區號。
// 寄海外時隱藏縣市與鄉鎮市區。
export default class extends Controller {
  static targets = ["region", "city", "district", "zip", "taiwanOnly"]
  static values = { zipcodes: Object } // { "台北市": { "中正區": "100", ... }, ... }

  connect() {
    this.regionChanged()
  }

  regionChanged() {
    const isTaiwan = this.regionTarget.value.startsWith("tw_")
    this.taiwanOnlyTarget.hidden = !isTaiwan
  }

  cityChanged() {
    const districts = this.zipcodesValue[this.cityTarget.value] || {}
    this.districtTarget.innerHTML = ""
    this.districtTarget.add(new Option("請選擇鄉鎮市區", ""))
    Object.keys(districts).forEach((name) => this.districtTarget.add(new Option(name, name)))
    this.zipTarget.value = ""
  }

  districtChanged() {
    const districts = this.zipcodesValue[this.cityTarget.value] || {}
    this.zipTarget.value = districts[this.districtTarget.value] || ""
  }
}
