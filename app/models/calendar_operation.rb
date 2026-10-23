class CalendarOperation < ApplicationRecord
  # `hash` is reserved by Active Record: read with content_hash_of, write with raw_insert_all.
  self.ignored_columns = [ "hash" ]
end
