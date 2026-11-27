# 結帳表單的欄位與驗證（收件、聯絡、發票、付款方式）。
# 它不是資料表，只負責「使用者填的東西合不合規則」；金額相關的檢查在 Checkout::PriceCalculator。
class CheckoutForm
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :checkout_token, :string
  attribute :reward_id, :integer
  attribute :addon_ids, default: -> { [] }
  attribute :discount_code, :string
  attribute :donation, :string
  attribute :payment_method, :string, default: "credit_card"
  attribute :ship_region, :string   # 沒有預設值：收件地點必須由使用者自己選
  attribute :ship_city, :string
  attribute :ship_district, :string
  attribute :ship_zip, :string
  attribute :ship_address, :string
  attribute :recipient_name, :string
  attribute :recipient_phone, :string
  attribute :invoice_type, :string, default: "personal"
  attribute :carrier_code, :string
  attribute :company_tax_id, :string
  attribute :company_title, :string

  PHONE_FORMAT   = /\A09\d{8}\z/                 # 台灣手機：09 開頭共 10 碼
  CARRIER_FORMAT = /\A\/[0-9A-Z.+\-]{7}\z/       # 手機條碼載具：/ 加 7 碼
  TAX_ID_FORMAT  = /\A\d{8}\z/                   # 統一編號：8 碼數字
  ZIP_FORMAT     = /\A\d{3}(\d{2,3})?\z/         # 郵遞區號：3 碼、3+2 或 3+3

  validates :ship_region, presence: { message: "請選擇收件地點" }
  validates :recipient_name, presence: { message: "請填寫收件人" }
  validates :ship_address, presence: { message: "請填寫地址" }
  validates :ship_zip, format: { with: ZIP_FORMAT, message: "郵遞區號格式不正確" }
  validates :recipient_phone, format: { with: PHONE_FORMAT, message: "請填寫 09 開頭的 10 碼手機號碼" }
  validates :invoice_type, inclusion: { in: %w[personal company], message: "請選擇發票類型" }
  validate :taiwan_address
  validate :invoice_details

  # 正規化：電話去掉空白與 -；載具轉大寫
  def recipient_phone = super.to_s.gsub(/[\s-]/, "")
  def carrier_code = super.to_s.strip.upcase.presence
  def addon_ids = Array(super).compact_blank

  # 縣市、鄉鎮市區只有寄台灣時才有意義。
  # 寄海外時一律當成沒填：瀏覽器可能還帶著之前選過的值（例如先選金門、再改海外），
  # 不丟掉的話訂單會記成「海外＋金門」（spec §3.4）。
  def ship_city = taiwan? ? super.presence : nil
  def ship_district = taiwan? ? super.presence : nil

  def taiwan? = ship_region.to_s.start_with?("tw_")

  # 付款方式要另外檢查（0 元訂單不需要付款方式，所以不放在一般驗證裡）
  def validate_payment_method!
    return if Payments::Registry.available?(payment_method)

    errors.add(:payment_method, Payments::Registry.known?(payment_method) ? "此付款方式尚未開放" : "請選擇付款方式")
  end

  private

  # 寄送台灣時，縣市與鄉鎮市區必填（海外只需要地址與郵遞區號）
  # 台灣地址：縣市要屬於所選的收件地點、鄉鎮市區要屬於所選的縣市（spec §3.4）。
  # 正常在畫面上操作不會選到不一致的組合（下拉只列出對應的選項），這裡擋的是竄改表單或舊頁面送來的資料；
  # 不擋的話，選「本島」卻填金門會用本島運費寄到離島。
  def taiwan_address
    return unless taiwan?

    if ship_city.blank?
      errors.add(:ship_city, "請選擇縣市")
    elsif !TwZipcode.cities_for(ship_region).include?(ship_city)
      errors.add(:ship_city, "縣市與收件地點不符，請重新選擇")
    end

    if ship_district.blank?
      errors.add(:ship_district, "請選擇鄉鎮市區")
    elsif ship_city.present? && !TwZipcode.districts(ship_city).key?(ship_district)
      errors.add(:ship_district, "鄉鎮市區與縣市不符，請重新選擇")
    end
  end

  def invoice_details
    if invoice_type == "company"
      errors.add(:company_tax_id, "統一編號須為 8 碼數字") unless company_tax_id.to_s.match?(TAX_ID_FORMAT)
      errors.add(:company_title, "請填寫公司抬頭") if company_title.blank?
    elsif carrier_code && !carrier_code.match?(CARRIER_FORMAT)
      errors.add(:carrier_code, "手機載具格式為 / 加 7 碼（例：/AB1CD23）")
    end
  end
end
