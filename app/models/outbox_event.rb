class OutboxEvent < ApplicationRecord
  self.table_name = "outbox"
  self.inheritance_column = nil
end
