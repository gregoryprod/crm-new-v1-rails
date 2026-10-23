# Server-side staff session: the cookie holds a random token, the table only its HMAC.
class StaffSession < ApplicationRecord
  self.table_name = "sessions"
  belongs_to :user
end
