# JSON exactly as the previous Node app produced it: timestamps as ISO strings with
# milliseconds and "Z" (JavaScript Date#toJSON), camelCase row keys, no HTML escaping.
module Json
  module_function

  def iso(time)
    time&.utc&.iso8601(3)
  end

  # Converts values for JSON: times → ISO strings, nested hashes/arrays recursively.
  def plain(value)
    case value
    when Time, ActiveSupport::TimeWithZone, DateTime then iso(value.to_time)
    when Hash then value.each_with_object({}) { |(k, v), out| out[k.to_s] = plain(v) }
    when Array then value.map { |v| plain(v) }
    when BigDecimal then value.to_i == value ? value.to_i : value.to_f
    # JavaScript has one number type: 1.0 prints as 1.
    when Float then value.finite? && value == value.floor && value.abs < 1e21 ? value.to_i : value
    else value
    end
  end

  def dump(value)
    JSON.generate(plain(value))
  end

  def dump_or_nil(value)
    value.nil? ? nil : dump(value)
  end

  # Key-order independent JSON (jsonb does not keep key order).
  def canonical(value)
    JSON.generate(sort_keys(plain(value)))
  end

  def sort_keys(value)
    case value
    when Hash then value.keys.sort.each_with_object({}) { |k, out| out[k] = sort_keys(value[k]) }
    when Array then value.map { |v| sort_keys(v) }
    else value
    end
  end

  # Database columns that the Node schema exposed under a different property name.
  RENAMED = { "start_at" => "start", "end_at" => "end" }.freeze

  def camel_key(column)
    RENAMED.fetch(column) { column.camelize(:lower) }
  end

  # A full row as Drizzle returned it: every column, camelCase keys, Date values.
  def row(record)
    record.attributes.each_with_object({}) do |(column, value), out|
      out[camel_key(column)] = value
    end
  end

  def sha256(text)
    Digest::SHA256.hexdigest(text)
  end
end
