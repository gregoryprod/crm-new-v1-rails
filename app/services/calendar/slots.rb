module Calendar
  # Slot arithmetic in UTC. The clinic calendar uses Moscow time, which has had a fixed
  # +03:00 offset (no DST) since 2014.
  module Slots
    OFFSET = "+03:00"
    STEP = 15 * 60

    Range = Data.define(:start, :end)

    module_function

    def overlaps?(a, b)
      a_start, a_end = bounds(a)
      b_start, b_end = bounds(b)
      a_start < b_end && b_start < a_end
    end

    def bounds(value)
      value.respond_to?(:start_at) ? [ value.start_at, value.end_at ] : [ value.start, value.end ]
    end

    def valid_day?(day)
      return false unless day.is_a?(String) && day.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      Date.strptime(day, "%Y-%m-%d").iso8601 == day && day >= "2000-01-01" && day <= "2100-12-31"
    rescue Date::Error
      false
    end

    def day_range(day, days = 1)
      raise ArgumentError, "Invalid day range" unless valid_day?(day) && [ 1, 7 ].include?(days)
      start = Time.iso8601("#{day}T00:00:00#{OFFSET}").utc
      Range.new(start:, end: start + days * 86_400)
    end

    # YYYY-MM-DD of an instant in Moscow.
    def moscow_day(time)
      time.getlocal(OFFSET).strftime("%Y-%m-%d")
    end

    def available(shifts, blocked, day, duration_minutes, now = Time.current)
      range = day_range(day)
      duration = duration_minutes * 60
      slots = {}
      shifts.select { |shift| overlaps?(shift, range) }.each do |shift|
        shift_start, shift_end = bounds(shift)
        steps = [ 0, ((range.start - shift_start) / STEP).ceil ].max
        t = shift_start + steps * STEP
        while t < range.end && t + duration <= shift_end
          slot = Range.new(start: t, end: t + duration)
          if t > now && blocked.none? { |b| overlaps?(b, slot) }
            slots[t.to_r] = { "start" => Json.iso(slot.start), "end" => Json.iso(slot.end) }
          end
          t += STEP
        end
      end
      slots.values.sort_by { |slot| slot["start"] }
    end
  end
end
