# Immutable import evidence: the source card as it was imported.
class LegacyClientRecord < ApplicationRecord
  # `hash` is reserved by Active Record: read with content_hash_of, write with raw_insert_all.
  self.ignored_columns = [ "hash" ]
  self.primary_key = "source_id"
  belongs_to :client
end
