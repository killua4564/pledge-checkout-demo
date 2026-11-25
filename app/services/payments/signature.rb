# callback 簽章：用來確認通知真的是金流送來的，而且內容沒被改過。
#
# 原理（HMAC-SHA256）：金流和我們事先共享一把密鑰。
# 金流送通知時，用密鑰對「時間戳 + 內文」算出一串簽章放在 header。
# 我們收到後用同一把密鑰再算一次，兩邊一樣才相信。沒有密鑰的人算不出正確簽章。
#
# 另外檢查時間戳：太舊的通知（超過 5 分鐘）不接受，避免有人把以前截到的通知重送一次（重放攻擊）。
module Payments
  module Signature
    TOLERANCE = 5.minutes

    module_function

    def sign(secret:, timestamp:, body:)
      OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body}")
    end

    def verify!(secret:, timestamp:, signature:, body:, now: Time.current)
      raise SignatureError, "缺少簽章或時間戳" if signature.blank? || timestamp.blank?
      raise SignatureError, "時間戳格式錯誤" unless timestamp.to_s.match?(/\A\d+\z/)
      raise SignatureError, "時間戳超過 #{TOLERANCE.inspect}，拒絕重放" if (now.to_i - timestamp.to_i).abs > TOLERANCE

      expected = sign(secret:, timestamp:, body:)
      # secure_compare：比對時間固定，不會因為「前幾個字對了」而比較慢，避免被逐字猜出簽章
      raise SignatureError, "簽章不符" unless ActiveSupport::SecurityUtils.secure_compare(expected, signature.to_s)

      true
    end
  end
end
