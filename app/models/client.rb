class Client < ApplicationRecord
  has_many :patients
  has_many :leads
  has_many :consents
  has_one :legacy_client_record

  def full_name
    [ last_name, first_name ].reject(&:blank?).join(" ")
  end
end
