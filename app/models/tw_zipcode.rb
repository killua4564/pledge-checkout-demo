# 台灣郵遞區號資料（讀 config/tw_zipcodes.yml）。
# 回傳 { "台北市" => { "中正區" => "100", ... }, ... }
module TwZipcode
  def self.all
    @all ||= YAML.load_file(Rails.root.join("config/tw_zipcodes.yml")).freeze
  end
end
