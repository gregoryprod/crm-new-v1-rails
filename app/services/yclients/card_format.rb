module Yclients
  # YCLIENTS client cards in the shape the full workspace (`public/full-crm`) expects.
  # History rows keep their source values (the original status moves to `sourceAttendance`);
  # card-level `visits`, `firstDate`, `lastDate`, `lastDoctor` and `historyCostCents` are
  # derived and recomputed from the rows. Pure and idempotent.
  module CardFormat
    VERSION = "yclients-card-v2"
    ATTENDED = "пришёл"
    ATTENDANCE = {
      "Клиент пришёл" => ATTENDED, "Клиент не пришёл" => "не пришёл", "Ожидание" => "ожидание",
      "Клиент подтвердил" => "подтвердил",
      "1" => ATTENDED, "-1" => "не пришёл", "0" => "ожидание", "2" => "подтвердил"
    }.freeze
    DAY = /\A\d{4}-\d{2}-\d{2}/

    module_function

    def str(value) = value.is_a?(String) ? value : ""

    def attended?(row)
      !row["deleted"] && str(row["attendance"]).downcase.tr("ё", "е") == "пришел"
    end

    # JavaScript String(value ?? "") for the values found in source rows.
    def js_string(value)
      case value
      when nil then ""
      when true, false then value.to_s
      when Float then value == value.floor && value.abs < 1e21 ? value.to_i.to_s : value.to_s
      else value.to_s
      end
    end

    def normalize_row(row)
      source_attendance = row["sourceAttendance"].is_a?(String) ? row["sourceAttendance"] : js_string(row.fetch("attendance", nil))
      when_value = str(row["sourceDateTime"]).presence || str(row["date"])
      doctor_source_id = row["doctorSourceId"].nil? ? nil : js_string(row["doctorSourceId"])
      doctor_id = if row["doctorId"].is_a?(String)
        row["doctorId"]
      elsif doctor_source_id.present?
        CryptoHelpers.legacy_id("doctor", doctor_source_id)
      end
      row.merge(
        "date" => DAY.match?(when_value) ? when_value[0, 10] : nil,
        "attendance" => ATTENDANCE.fetch(source_attendance, source_attendance),
        "sourceAttendance" => source_attendance,
        "deleted" => truthy?(row["deleted"]),
        "doctorId" => doctor_id,
        # Source local time first, record id as a stable tie-breaker.
        "sourceSortKey" => "#{when_value}|#{js_string(row['id']).rjust(12, '0')}"
      )
    end

    def truthy?(value)
      !(value.nil? || value == false || value == 0 || value == "" || (value.is_a?(Float) && value.nan?))
    end

    def normalize_card(card)
      history = card["history"].map { |row| normalize_row(row) }
      visits = history.select { |row| attended?(row) && row["date"].is_a?(String) }.sort_by { |row| str(row["sourceSortKey"]) }
      costs = visits.map { |row| row["costCents"] }
      safe = costs.all? { |cost| cost.is_a?(Integer) && cost.abs <= 9_007_199_254_740_991 }
      card.merge(
        "history" => history,
        "visits" => visits.length,
        "firstDate" => visits.first&.dig("date"),
        "lastDate" => visits.last&.dig("date"),
        "lastDoctor" => str(visits.last&.dig("doctor")).presence,
        "historyCostCents" => safe ? costs.sum : nil,
        "directions" => card["directions"].is_a?(Array) ? card["directions"] : [],
        "issues" => card["issues"].is_a?(Array) ? card["issues"] : [],
        "cardFormat" => VERSION
      )
    end
  end
end
