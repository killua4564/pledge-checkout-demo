# 台灣郵遞區號資料（讀 config/tw_zipcodes.yml）。
# 回傳 { "台北市" => { "中正區" => "100", ... }, ... }
#
# 也負責「收件地點 ↔ 縣市」的對應（spec §3.4）：
# 運費跟著收件地點（本島／離島）走，所以縣市必須屬於所選的收件地點，
# 否則選「本島」卻填金門，就會用本島運費寄到離島、少收運費。
module TwZipcode
  # 離島縣市。連江縣（馬祖）目前沒有收錄郵遞區號資料，先列在這裡，日後補資料時不用再改規則
  ISLAND_CITIES = %w[澎湖縣 金門縣 連江縣].freeze

  def self.all
    @all ||= YAML.load_file(Rails.root.join("config/tw_zipcodes.yml")).freeze
  end

  # 某個收件地點可以選的縣市。海外或還沒選收件地點時沒有縣市可選（回傳空陣列）
  def self.cities_for(region)
    case region.to_s
    when "tw_island" then all.keys.select { |city| ISLAND_CITIES.include?(city) }
    when "tw_main"   then all.keys.reject { |city| ISLAND_CITIES.include?(city) }
    else []
    end
  end

  # 給結帳頁的 Stimulus 用：{ "tw_main" => [縣市...], "tw_island" => [縣市...] }
  def self.cities_by_region
    { "tw_main" => cities_for("tw_main"), "tw_island" => cities_for("tw_island") }
  end

  # 某個縣市的鄉鎮市區 => 郵遞區號
  def self.districts(city) = all[city] || {}
end
