# Baseline: the schema built by the previous Node app (Drizzle migrations 0000–0006).
#
# On an empty database the original SQL files run verbatim, in order, and the Drizzle
# journal is written too, so the database stays usable by either application during the
# transition. On a database the Node app already migrated, nothing is executed: the
# journal must show all seven migrations, otherwise the migration stops.
class AdoptDrizzleSchema < ActiveRecord::Migration[8.1]
  SQL_DIR = Rails.root.join("db/drizzle")
  # tag => journal "when" (milliseconds), from drizzle/meta/_journal.json.
  JOURNAL = {
    "0000_init" => 1791716670850,
    "0001_strange_gressill" => 1791730027653,
    "0002_calendar_and_versions" => 1792076731020,
    "0003_legacy_import_and_public_booking" => 1792078259682,
    "0004_legacy_receipt_compatibility" => 1792078384688,
    "0005_appointment_attendance_payments" => 1792079879528,
    "0006_full_crm" => 1792250000000
  }.freeze

  def up
    if table_exists?(:users)
      applied = select_value(<<~SQL).to_i
        SELECT count(*) FROM drizzle.__drizzle_migrations
        WHERE created_at = ANY(ARRAY[#{JOURNAL.values.join(',')}]::bigint[])
      SQL
      raise "Existing schema is not at Drizzle migration 0006 (found #{applied}/#{JOURNAL.size})" unless applied == JOURNAL.size
      return
    end

    execute "CREATE SCHEMA IF NOT EXISTS drizzle"
    execute <<~SQL
      CREATE TABLE IF NOT EXISTS drizzle.__drizzle_migrations (
        id SERIAL PRIMARY KEY, hash text NOT NULL, created_at bigint
      )
    SQL
    JOURNAL.each do |tag, created_at|
      sql = SQL_DIR.join("#{tag}.sql").read
      sql.split("--> statement-breakpoint").map(&:strip).reject(&:empty?).each { |statement| execute statement }
      execute <<~SQL
        INSERT INTO drizzle.__drizzle_migrations (hash, created_at)
        VALUES (#{quote(Digest::SHA256.hexdigest(sql))}, #{created_at})
      SQL
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
