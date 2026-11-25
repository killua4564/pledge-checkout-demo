# 金額工具：處理「幣別有幾位小數」這件事。
#
# 為什麼需要？同樣是數字 20，在 TWD 是 20 元，在 USD 可以是 20.49 元。
# 計算後依幣別捨入、顯示時加上幣別符號，都在這裡統一處理。
module Money
  # 每個幣別的小數位數。新增幣別時在這裡加一行。
  PRECISION = { "TWD" => 0, "USD" => 2, "JPY" => 0 }.freeze

  SYMBOLS = { "TWD" => "NT$", "USD" => "US$", "JPY" => "¥" }.freeze

  class InvalidAmount < StandardError; end

  module_function

  def precision(currency)
    PRECISION.fetch(currency) { raise ArgumentError, "不支援的幣別：#{currency}" }
  end

  # 依幣別捨入（四捨五入），永遠回傳 BigDecimal（精確小數），不會出現 float
  def round(amount, currency)
    BigDecimal(amount.to_s).round(precision(currency), BigDecimal::ROUND_HALF_UP)
  end

  # 把使用者輸入的文字轉成金額，例如加碼贊助欄位。
  # 空白 → 0；負數、文字、小數位數超過幣別允許 → 丟 InvalidAmount
  def parse(input, currency)
    text = input.to_s.strip.delete(",")
    return BigDecimal("0") if text.empty?
    raise InvalidAmount, "請輸入數字" unless text.match?(/\A\d+(\.\d+)?\z/)

    value = BigDecimal(text)
    decimals = text.include?(".") ? text.split(".").last.length : 0
    if decimals > precision(currency)
      raise InvalidAmount, precision(currency).zero? ? "#{currency} 只能輸入整數" : "最多 #{precision(currency)} 位小數"
    end
    value
  end

  # 顯示用：NT$ 5,800 / US$ 20.49
  def format(amount, currency)
    rounded = round(amount, currency)
    number = ActiveSupport::NumberHelper.number_to_delimited(
      ActiveSupport::NumberHelper.number_to_rounded(rounded, precision: precision(currency))
    )
    "#{SYMBOLS.fetch(currency, currency)} #{number}"
  end
end
