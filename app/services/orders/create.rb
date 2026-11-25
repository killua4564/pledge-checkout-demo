# 建立訂單並開始付款。
#
# 流程：
#   1. 同一個 checkout_token 已經建過訂單 → 直接回傳那張訂單（防止連點兩次）
#   2. 驗證表單欄位
#   3. 伺服器重新計算金額（不看前端送來的任何金額）
#   4. 資料庫交易內：佔名額 → 建訂單 → 存加購、折扣明細（0 元訂單直接轉已付款）
#   5. 交易成功後，請金流 adapter 建立付款，取得下一步要去的網址
#
# 為什麼第 5 步放在交易外？真實金流要打外部 API，可能很慢或失敗。
# 不應該讓資料庫交易一直開著等外部回應；失敗時就把訂單轉為 failed 並釋放名額。
module Orders
  class Create
    Result = Data.define(:order, :form, :quote, :errors, :next_path) do
      def success? = errors.empty?
    end

    def self.call(reward:, params:) = new(reward:, params:).call

    def initialize(reward:, params:)
      @reward = reward
      @form = CheckoutForm.new(params)
    end

    def call
      # 1. 防重複送出
      if (existing = Order.find_by(checkout_token: @form.checkout_token))
        return success(existing)
      end

      # 2 + 3. 驗證欄位、重新計算金額
      quote = Checkout::PriceCalculator.call(
        reward: @reward,
        addon_ids: @form.addon_ids,
        discount_code: @form.discount_code,
        region: @form.ship_region,
        donation: @form.donation
      )
      @form.validate
      @form.validate_payment_method! unless quote.free?   # 0 元訂單不需要付款方式

      errors = @form.errors.map(&:message) + quote.errors
      errors << quote.discount_error if quote.discount_error   # 下單時折扣碼無效要擋下來
      errors << "結帳資料已過期，請重新整理頁面" if @form.checkout_token.blank?
      return failure(errors, quote) if errors.any?

      # 4. 佔名額 + 建訂單（同一個交易：任何一步失敗，全部回復，名額也不會被佔走）
      order = Order.transaction do
        Inventory.reserve!(@reward.id)
        build_order(quote)
      end

      # 5. 開始付款
      return success(order) if order.paid?   # 0 元訂單已經完成

      start = Payments::Registry.fetch(order.payment_method).create_payment(order)
      success(order, start.next_path)
    rescue Inventory::SoldOut
      failure(["很抱歉，這個方案的名額已經被搶完了"], quote)
    rescue ActiveRecord::RecordNotUnique
      # 兩個相同的請求同時送達：第二個撞到 checkout_token 唯一索引，回傳第一個建好的訂單
      success(Order.find_by!(checkout_token: @form.checkout_token))
    rescue Payments::Error => e
      Orders::Transition.call(order, :fail, reason: "建立付款失敗：#{e.message}") if order&.pending_payment?
      failure(["付款建立失敗，請稍後再試"], quote)
    end

    private

    def build_order(quote)
      order = Order.create!(
        checkout_token: @form.checkout_token,
        project: @reward.project,
        reward: @reward,
        currency: quote.currency,
        reward_amount: quote.reward_amount,
        addons_amount: quote.addons_amount,
        discount_amount: quote.discount_amount,
        shipping_amount: quote.shipping_amount,
        donation_amount: quote.donation_amount,
        total_amount: quote.total_amount,
        payment_method: quote.free? ? "free" : @form.payment_method,
        expires_at: quote.free? ? nil : Time.current + expire_minutes.minutes,
        ship_region: @form.ship_region,
        ship_city: @form.ship_city,
        ship_district: @form.ship_district,
        ship_zip: @form.ship_zip,
        ship_address: @form.ship_address,
        recipient_name: @form.recipient_name,
        recipient_phone: @form.recipient_phone,
        invoice_type: @form.invoice_type,
        carrier_code: @form.invoice_type == "personal" ? @form.carrier_code : nil,
        company_tax_id: @form.invoice_type == "company" ? @form.company_tax_id : nil,
        company_title: @form.invoice_type == "company" ? @form.company_title : nil
      )

      quote.addons.each do |addon|
        order.order_addons.create!(addon: addon, title: addon.title, price: addon.price)
      end

      if quote.discount_code
        order.create_order_discount!(discount_code: quote.discount_code, code: quote.discount_code.code, amount: quote.discount_amount)
      end

      # 0 元訂單：不經金流，直接轉已付款（一樣走狀態機，留下紀錄）
      Orders::Transition.call(order, :pay, reason: "金額為 0，免付款") if quote.free?

      order
    end

    def expire_minutes
      settings = Rails.configuration.x.checkout
      @form.payment_method == "atm" ? settings.atm_expire_minutes : settings.card_expire_minutes
    end

    def success(order, next_path = nil)
      Result.new(order: order, form: @form, quote: nil, errors: [], next_path: next_path || Rails.application.routes.url_helpers.order_path(order))
    end

    def failure(errors, quote)
      Result.new(order: nil, form: @form, quote: quote, errors: errors.uniq, next_path: nil)
    end
  end
end
