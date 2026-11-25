# 名額的佔用與釋放。
#
# 關鍵：不要「先查還剩幾個 → 再扣」。兩個人同時查到「剩 1」，就會兩個人都扣成功（超賣）。
# 正確做法是把「檢查」和「扣除」寫在同一句 SQL：
#
#   UPDATE rewards SET quota_taken = quota_taken + 1
#   WHERE id = ? AND quota_taken < quota_total
#
# 資料庫會保證這句是原子的（一次做完、不會被插隊）。影響 1 列 = 搶到；影響 0 列 = 名額已滿。
module Inventory
  class SoldOut < StandardError; end

  module_function

  # 佔用一個名額。搶不到就丟 SoldOut。
  def reserve!(reward_id)
    updated = Reward.where(id: reward_id)
                    .where("quota_taken < quota_total")
                    .update_all("quota_taken = quota_taken + 1, updated_at = CURRENT_TIMESTAMP")
    raise SoldOut, "名額已被搶完" if updated.zero?
  end

  # 釋放一個名額（訂單失敗、取消、過期時）。
  # 呼叫端（Orders::Transition）保證每張訂單只會呼叫一次。
  def release(reward_id)
    Reward.where(id: reward_id)
          .where("quota_taken > 0")
          .update_all("quota_taken = quota_taken - 1, updated_at = CURRENT_TIMESTAMP")
  end
end
