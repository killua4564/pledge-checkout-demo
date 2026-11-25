# 運費：跟著方案、依地區設定。
#   運費 = fee + (有選加購 ? addon_fee : 0)
class ShippingRate < ApplicationRecord
  REGIONS = %w[tw_main tw_island overseas].freeze

  belongs_to :reward

  validates :region, inclusion: { in: REGIONS }

  def taiwan? = region.start_with?("tw_")

  def fee_for(with_addons:)
    with_addons ? fee + addon_fee : fee
  end
end
