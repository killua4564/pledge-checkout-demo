# 建立訂單、訂單狀態頁、取消訂單
class OrdersController < ApplicationController
  # POST /orders
  def create
    # 驗證失敗時會重新顯示結帳頁，所以和結帳頁一樣先載入專案的加購
    @reward = Reward.includes({ project: :addons }, :shipping_rates).find(checkout_params[:reward_id])
    result = Orders::Create.call(reward: @reward, params: checkout_params)

    if result.success?
      redirect_to result.next_path, status: :see_other
    else
      # 驗證失敗：回到結帳頁，保留已填資料並顯示錯誤
      @project = @reward.project
      @form = result.form
      @errors = result.errors
      @quote = result.quote || Checkout::PriceCalculator.call(reward: @reward)
      render "checkouts/show", status: :unprocessable_entity
    end
  end

  # GET /orders/:public_id
  # 依訂單狀態顯示不同內容（處理中、ATM 繳費資訊、完成、失敗…）。
  # 注意：網址上帶任何參數都不會改變狀態，只有金流 callback 能改。
  def show
    @order = Order.includes(:reward, :project, :order_addons, :order_discount, :payments).find_by!(public_id: params[:public_id])
  end

  # POST /orders/:public_id/cancel
  def cancel
    order = Order.find_by!(public_id: params[:public_id])
    Orders::Transition.call(order, :cancel, reason: "使用者取消")
    redirect_to order_path(order), status: :see_other
  rescue Order::InvalidTransition
    redirect_to order_path(order), status: :see_other, alert: "這張訂單已經無法取消"
  end

  private

  # 只接受「選了什麼」的欄位。前端就算偷塞 total、price 等金額欄位，也會在這裡被丟掉
  def checkout_params
    params.require(:checkout).permit(
      :checkout_token, :reward_id, :discount_code, :donation, :payment_method,
      :ship_region, :ship_city, :ship_district, :ship_zip, :ship_address,
      :recipient_name, :recipient_phone,
      :invoice_type, :carrier_code, :company_tax_id, :company_title,
      addon_ids: []
    )
  end
end
