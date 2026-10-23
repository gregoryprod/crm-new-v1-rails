# Insert-only history of changes; `actor` is a user id or "system".
class AuditLog < ApplicationRecord
  self.table_name = "audit_log"

  # Call inside the transaction that performs the change. `at` is the wall clock of the
  # change (after row locks were taken), not the transaction start.
  def self.write!(actor:, entity:, entity_id:, action:, before: nil, after: nil)
    connection.exec_insert(
      "INSERT INTO audit_log (actor, entity, entity_id, action, before, after, at) " \
      "VALUES ($1, $2, $3, $4, $5::jsonb, $6::jsonb, clock_timestamp())",
      "AuditLog Write",
      [ actor, entity, entity_id, action, Json.dump_or_nil(before), Json.dump_or_nil(after) ]
    )
  end
end
