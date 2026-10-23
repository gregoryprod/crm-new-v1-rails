class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Every table keeps the column names of the previous Node app; enums are PostgreSQL enums
  # read and written as strings.
  def self.sql(fragment, *binds)
    sanitize_sql_array([ fragment, *binds ])
  end

  # Inserts rows with plain SQL, including columns hidden from Active Record (`hash` is a
  # reserved method name, so models ignore that column). Hashes/arrays are stored as jsonb.
  # Returns the `returning` column of the inserted rows.
  def self.raw_insert_all(rows, returning: nil, on_conflict_do_nothing: false)
    return [] if rows.empty?
    columns = rows.first.keys.map(&:to_s)
    unknown = columns - connection.columns(table_name).map(&:name)
    raise ArgumentError, "Unknown columns for #{table_name}: #{unknown.join(', ')}" if unknown.any?
    values = rows.map do |row|
      "(" + columns.map { |c| connection.quote(serialize_raw(row[c] || row[c.to_sym])) }.join(", ") + ")"
    end
    sql = +"INSERT INTO #{quoted_table_name} (#{columns.map { |c| connection.quote_column_name(c) }.join(', ')}) VALUES #{values.join(', ')}"
    sql << " ON CONFLICT DO NOTHING" if on_conflict_do_nothing
    sql << " RETURNING #{connection.quote_column_name(returning)}" if returning
    returning ? connection.select_values(sql) : (connection.execute(sql) && [])
  end

  def self.serialize_raw(value)
    case value
    when Hash, Array then Json.dump(value)
    when Time, ActiveSupport::TimeWithZone then value.utc.iso8601(6)
    else value
    end
  end

  # Value of the hidden `hash` column.
  def self.content_hash_of(conditions)
    where(conditions).pick(Arel.sql("#{quoted_table_name}.hash"))
  end
end
