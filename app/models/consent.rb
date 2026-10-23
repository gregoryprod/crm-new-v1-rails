class Consent < ApplicationRecord
  self.inheritance_column = nil
  belongs_to :client
end
