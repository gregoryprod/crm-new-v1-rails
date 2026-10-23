module Validation
  # Tiny strict validators mirroring the zod schemas of the Node app: unknown keys are
  # rejected, defaults are applied, and the result keeps the schema's key order (it feeds
  # idempotency hashes).
  module Check
    ISO_DATETIME = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)\z/
    MINUTE = /\A([01]\d|2[0-3]):[0-5]\d\z/
    INT_MAX = 2_147_483_647

    module_function

    def fail!
      raise Invalid
    end

    def object(value, keys)
      fail! unless value.is_a?(Hash) && (value.keys - keys).empty?
      value
    end

    def uuid(value)
      CryptoHelpers.uuid?(value) ? value : fail!
    end

    def int(value, min: nil, max: nil)
      fail! unless value.is_a?(Integer) || (value.is_a?(Float) && value.finite? && value == value.floor)
      value = value.to_i
      fail! if (min && value < min) || (max && value > max)
      value
    end

    def nullable_int(value, **bounds)
      value.nil? ? nil : int(value, **bounds)
    end

    def string(value, min: 0, max: nil, trim: false)
      fail! unless value.is_a?(String)
      value = value.strip if trim
      fail! if value.length < min || (max && value.length > max)
      value
    end

    def enum(value, allowed)
      allowed.include?(value) ? value : fail!
    end

    def day(value)
      Calendar::Slots.valid_day?(value) ? value : fail!
    end

    def minute(value)
      value.is_a?(String) && MINUTE.match?(value) ? value : fail!
    end

    def iso_datetime(value)
      fail! unless value.is_a?(String) && ISO_DATETIME.match?(value)
      Time.iso8601(value)
      value
    rescue ArgumentError
      fail!
    end

    def literal(value, expected)
      value == expected ? value : fail!
    end

    def present?(hash, key)
      hash.key?(key) && !hash[key].nil?
    end
  end
end
