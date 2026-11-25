# 唯一算錢的地方。
#
# 「即時預覽金額」和「實際建立訂單」都呼叫這個類別，所以畫面上看到的金額和實際收的錢一定一樣。
# 前端只送「選了什麼」（方案、加購、折扣碼、地區、加碼金額），從不送金額，前端送來的金額一律不看。
#
# 計算規則（docs/spec.md §5）：
#   總額 = 方案金額 + 加購金額 − 折扣 + 運費 + 加碼贊助
#   - 折扣只折方案金額，最多折到 0（所以總額不會是負數）
#   - 運費 = 地區運費 + (有加購 ? 加購運費 : 0)
#   - 還沒選收件地點時運費「未知」：總額先不含運費，而且不能下單。
#     不替使用者假設「本島」，否則離島、海外的人沒注意就會用錯的運費成立訂單。
module Checkout
  class PriceCalculator
    # 計算結果。errors 有內容代表「不能下單」；discount_error 是折扣碼的問題（預覽時只提示）。
    Quote = Data.define(
      :currency, :reward_amount, :addons_amount, :discount_amount,
      :shipping_amount, :donation_amount, :total_amount,
      :addons, :discount_code, :discount_error, :shipping_rate, :shipping_pending, :errors
    ) do
      # 能不能下單：沒有錯誤，而且運費已經確定
      def valid? = errors.empty? && !shipping_pending
      # 還沒選收件地點，運費未知
      def shipping_pending? = shipping_pending
      def free? = total_amount.zero?
      def money(amount) = Money.format(amount, currency)
    end

    def self.call(**args) = new(**args).call

    # reward:        要結帳的方案
    # addon_ids:     勾選的加購 id 陣列
    # discount_code: 使用者輸入的折扣碼文字
    # region:        收件地點（tw_main / tw_island / overseas）；空白代表還沒選
    # donation:      加碼贊助（使用者輸入的文字）
    def initialize(reward:, addon_ids: [], discount_code: nil, region: nil, donation: nil, now: Time.current)
      @reward = reward
      @project = reward.project
      @currency = @project.currency
      @addon_ids = Array(addon_ids).compact_blank.map(&:to_s).uniq   # 同一個加購重複送出只算一次
      @discount_text = discount_code
      @region = region.presence   # 不給預設值，見檔案開頭說明
      @donation_text = donation
      @now = now
      @errors = []
    end

    def call
      reward_amount = @reward.price

      # 加購：必須屬於同一個專案
      addons = find_addons
      addons_amount = addons.sum(BigDecimal("0"), &:price)

      # 折扣：只折方案金額，最多折到方案金額（不會變負數）
      discount_code, discount_error = DiscountCode.lookup(project: @project, text: @discount_text, now: @now)
      discount_amount = discount_code ? [discount_code.amount, reward_amount].min : BigDecimal("0")

      # 運費：依方案 + 收件地點查表。還沒選地點 → 運費未知（不是錯誤，只是還不能下單）
      shipping_pending = @region.nil?
      shipping_rate = @reward.shipping_rates.find { |rate| rate.region == @region } unless shipping_pending
      @errors << "此方案不支援寄送到這個地區" if !shipping_pending && !shipping_rate
      shipping_amount = shipping_rate ? shipping_rate.fee_for(with_addons: addons.any?) : BigDecimal("0")

      donation_amount = parse_donation

      total = reward_amount + addons_amount - discount_amount + shipping_amount + donation_amount

      Quote.new(
        currency: @currency,
        reward_amount: round(reward_amount),
        addons_amount: round(addons_amount),
        discount_amount: round(discount_amount),
        shipping_amount: round(shipping_amount),
        donation_amount: round(donation_amount),
        total_amount: round(total),
        addons: addons,
        discount_code: discount_code,
        discount_error: discount_error,
        shipping_rate: shipping_rate,
        shipping_pending: shipping_pending,
        errors: @errors
      )
    end

    private

    def find_addons
      found = @project.addons.where(id: @addon_ids).to_a
      @errors << "加購商品不存在或不屬於此專案" if found.size != @addon_ids.size
      found
    end

    def parse_donation
      amount = Money.parse(@donation_text, @currency)
      max = Rails.configuration.x.checkout.max_donation
      if amount > max
        @errors << "加碼贊助最多 #{Money.format(max, @currency)}"
        return BigDecimal("0")
      end
      amount
    rescue Money::InvalidAmount => e
      @errors << "加碼贊助金額有誤：#{e.message}"
      BigDecimal("0")
    end

    def round(amount) = Money.round(amount, @currency)
  end
end
