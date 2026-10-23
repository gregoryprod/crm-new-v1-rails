module FullCrm
  # Ruby port of public/full-crm/analytics-model.mjs: the workspace computes the same
  # per-card numbers in the browser, so the documents and the UI must never disagree.
  module AnalyticsModel
    LIFE = [
      { "id" => "first", "label" => "Первый визит" }, { "id" => "repeat", "label" => "Повторные" },
      { "id" => "regular", "label" => "Регулярные" }, { "id" => "dormant", "label" => "Давно не обращались" },
      { "id" => "no_visits", "label" => "Без состоявшихся обращений" }
    ].freeze
    EPOCH = Date.new(1970, 1, 1)
    MAX_SAFE = 9_007_199_254_740_991

    module_function

    def day(value)
      (Date.strptime(value, "%Y-%m-%d") - EPOCH).to_i
    rescue Date::Error, TypeError
      Float::NAN
    end

    def safe_integer?(value) = value.is_a?(Integer) && value.abs <= MAX_SAFE

    # JavaScript Math.round.
    def js_round(value) = (value + 0.5).floor

    # Approximation of String#localeCompare for keys and Russian labels: letters compare
    # case-insensitively and «ё» as «е» first, then by code point.
    def locale_key(value)
      text = value.to_s
      [ text.downcase.tr("ё", "е"), text ]
    end

    def lifecycle(records, days)
      return "no_visits" if records.zero?
      return "dormant" if days >= 90
      return "regular" if records >= 3
      records == 2 ? "repeat" : "first"
    end

    def xyz(count)
      return nil if count.zero?
      count >= 6 ? "X" : (count >= 2 ? "Y" : "Z")
    end

    # Equal costs stay together; a boundary-crossing group belongs to the earlier class.
    def abc_assignments(items)
      result = {}
      positive = items.select { |p| safe_integer?(p[:cost]) && p[:cost] > 0 }
        .sort { |a, b| (b[:cost] <=> a[:cost]).nonzero? || (locale_key(a[:id]) <=> locale_key(b[:id])) }
      total = positive.sum { |p| p[:cost] }
      cumulative = 0
      positive.chunk_while { |a, b| a[:cost] == b[:cost] }.each do |group|
        kind = cumulative < total * 0.8 ? "A" : (cumulative < total * 0.95 ? "B" : "C")
        group.each { |p| result[p[:id]] = kind }
        cumulative += group.sum { |p| p[:cost] }
      end
      items.each { |p| result[p[:id]] ||= p[:cost] == 0 ? "N" : "?" }
      result
    end


    def card_insight(history, cutoff)
      live = ->(r) { r["deleted"].nil? || r["deleted"] == false || r["deleted"] == 0 || r["deleted"] == "" }
      events = history.select { |r| live.(r) && r["attendance"].tr("ё", "е") == "пришел" && r["date"] <= cutoff }
        .sort_by { |r| r["date"] }
      dates = events.map { |r| r["date"] }.uniq
      known = events.select { |r| safe_integer?(r["costCents"]) }
      cost = known.length == events.length ? known.sum { |r| r["costCents"] } : nil
      days = events.any? ? day(cutoff) - day(events.last["date"]) : nil
      tenure = events.any? ? day(cutoff) - day(events.first["date"]) : nil
      return_at = lambda do |h|
        eligible = !tenure.nil? && tenure >= h
        { "eligible" => eligible,
          "returned" => eligible ? dates.any? { |d| day(d) > day(dates.first) && day(d) - day(dates.first) <= h } : nil }
      end
      recent = events.select { |r| day(cutoff) - day(r["date"]) < 90 }
      {
        "records" => events.length, "uniqueDays" => dates.length, "cost" => cost,
        "averageCostCents" => cost.nil? || events.empty? ? nil : js_round(cost.to_f / events.length),
        "daysSince" => days, "tenureDays" => tenure, "cohort" => events.first&.dig("date")&.slice(0, 7),
        "lifecycle" => lifecycle(events.length, days), "xyz" => xyz(events.length),
        "averageGapDays" => dates.length > 1 ? js_round((day(dates.last) - day(dates.first)).to_f / (dates.length - 1)) : nil,
        "zeroCost" => known.count { |r| r["costCents"] == 0 },
        "deleted" => history.count { |r| !live.(r) },
        "nonAttended" => history.count { |r| live.(r) && r["attendance"].tr("ё", "е") != "пришел" },
        "doctors" => events.map { |r| r["doctorId"].nil? ? r["doctor"] : r["doctorId"] }.uniq.length,
        "petNames" => history.map { |r| r["petName"] }.select { |n| truthy?(n) }.uniq,
        "cost90Cents" => recent.all? { |r| safe_integer?(r["costCents"]) } ? recent.sum { |r| r["costCents"] } : nil,
        "return30" => return_at.(30), "return60" => return_at.(60), "return90" => return_at.(90)
      }
    end

    def truthy?(value)
      !(value.nil? || value == false || value == 0 || value == "" || (value.is_a?(Float) && value.nan?))
    end
  end
end
