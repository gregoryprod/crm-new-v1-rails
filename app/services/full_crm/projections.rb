module FullCrm
  # Builds the `clients` / `doctors` / `analytics` documents of the full workspace from
  # PostgreSQL: the historical card payloads in legacy_client_records plus the doctor
  # directory. Derived data: same input → same documents and the same batchId.
  module Projections
    KEYS = %w[clients doctors analytics].freeze
    LOCK = "vpc-full-crm-projections"
    DAY = /\A\d{4}-\d{2}-\d{2}\z/
    METHOD = {
      "life" => "Жизненный цикл на дату среза считается по состоявшимся обращениям (запись не удалена, статус «пришёл»): одно — «Первый визит», два — «Повторные», три и более — «Регулярные»; 90 и более дней без обращения — «Давно не обращались»; карточки без состоявшихся обращений — отдельная группа.",
      "abc" => "ABC — по стоимости состоявшихся услуг за всю историю карточки до среза: A — карточки, дающие первые 80 % суммарной стоимости, B — следующие 15 %, C — остальные; карточки с равной стоимостью попадают в один класс; N — нулевая стоимость; при неизвестной стоимости класс не присваивается. Стоимость услуг не является оплатой.",
      "xyz" => "XYZ — по числу состоявшихся обращений до среза: X — 6 и более, Y — от 2 до 5, Z — одно."
    }.freeze

    Card = Data.define(:key, :client_id, :history, :payload)

    module_function

    def str(value) = value.is_a?(String) ? value : ""
    def attended?(row) = !AnalyticsModel.truthy?(row["deleted"]) && str(row["attendance"]).downcase.tr("ё", "е") == "пришел"
    def valid_date?(row) = DAY.match?(str(row["date"]))
    def model = AnalyticsModel

    def read_cards(preview_normalized: false)
      Client.left_joins(:legacy_client_record).order("clients.id")
        .pluck("clients.id", "legacy_client_records.source_key", "legacy_client_records.payload")
        .map do |client_id, source_key, payload|
          payload = payload.is_a?(String) ? JSON.parse(payload) : (payload || {})
          # Dry-run preview only: what the documents will be after the card normalization.
          if preview_normalized && source_key&.start_with?("yclients:") && payload["history"].is_a?(Array)
            payload = Yclients::CardFormat.normalize_card(payload)
          end
          Card.new(key: source_key || client_id, client_id:, history: payload["history"].is_a?(Array) ? payload["history"] : [], payload:)
        end
    end

    # Rows as the analytics model needs them; undated rows never count as visits.
    def insight_rows(history)
      history.map { |r| r.merge("attendance" => str(r["attendance"]), "date" => valid_date?(r) ? str(r["date"]) : "9999-12-31") }
    end

    def rate(eligible, returned)
      { "eligible" => eligible, "returned" => returned, "rate" => eligible.zero? ? nil : returned.to_f / eligible }
    end

    def build(cutoff: nil, preview_normalized: false)
      cards = read_cards(preview_normalized:)
      visit_dates = cards.flat_map { |c| c.history.select { |r| attended?(r) && valid_date?(r) }.map { |r| str(r["date"]) } }
      raise ProjectionError, "Cutoff must be YYYY-MM-DD" if !cutoff.nil? && !DAY.match?(cutoff)
      # Default: the latest completed visit, never in the future.
      today = Calendar::Slots.moscow_day(Time.current)
      latest = visit_dates.select { |d| d <= today }.max || ""
      cutoff ||= latest.presence || today

      insights = cards.to_h { |c| [ c.key, model.card_insight(insight_rows(c.history), cutoff) ] }
      abc = model.abc_assignments(cards.select { |c| insights[c.key]["records"] > 0 }.map { |c| { id: c.key, cost: insights[c.key]["cost"] } })
      per_card = cards.to_h { |c| [ c.key, insights[c.key].merge("abc" => abc[c.key] || "?") ] }
      visits = lambda do |c|
        c.history.select { |r| attended?(r) && valid_date?(r) && str(r["date"]) <= cutoff }.sort_by { |r| str(r["date"]) }
      end

      scope = lambda do |list|
        info = list.map { |c| [ c, per_card[c.key] ] }
        records = info.sum { |_, a| a["records"] }
        cost_cents = info.sum { |_, a| a["cost"] || 0 }
        money_totals = %w[sourceReportedPaidCents sourceReportedSpentCents sourceReportedBalanceCents].to_h do |field|
          known = list.map { |c| c.payload[field] }.select { |v| model.safe_integer?(v) }
          [ field, { "value" => known.any? ? known.sum : nil, "coverage" => known.length } ]
        end
        months = {}
        services = Hash.new(0)
        list.each do |c|
          visits.(c).each do |r|
            month = str(r["date"])[0, 7]
            m = months[month] ||= { records: 0, clients: Set.new, cost: 0 }
            m[:records] += 1
            m[:clients] << c.key
            m[:cost] += r["costCents"] if model.safe_integer?(r["costCents"])
            title = str(r["service"]).strip.presence || "Без названия услуги"
            services[title] += 1
          end
        end
        monthly = []
        keys = months.keys.sort
        if keys.any?
          y, m = keys.first.split("-").map(&:to_i)
          1200.times do
            key = format("%04d-%02d", y, m)
            break if key > keys.last
            v = months[key]
            monthly << { "month" => key, "records" => v ? v[:records] : 0, "clients" => v ? v[:clients].size : 0, "cost" => v ? v[:cost] : 0 }
            m += 1
            if m == 13
              m = 1
              y += 1
            end
          end
        end
        bucket = ->(label, test) { { "label" => label, "clients" => info.count { |_, a| test.(a) } } }
        cohort_map = {}
        info.each { |c, a| (cohort_map[a["cohort"]] ||= []) << [ c, a ] if a["cohort"] }
        ret = lambda do |xs, k|
          rate(xs.count { |_, a| a[k]["eligible"] }, xs.count { |_, a| a[k]["returned"] == true })
        end
        since = ->(a, lo, hi) { !a["daysSince"].nil? && a["daysSince"] > lo && (hi.nil? || a["daysSince"] <= hi) }
        {
          "clients" => list.length,
          "attendingClients" => info.count { |_, a| a["records"] > 0 },
          "notClassified" => info.count { |_, a| a["records"].zero? },
          "records" => records,
          "costCents" => cost_cents,
          "averageCostCents" => records.zero? ? nil : model.js_round(cost_cents.to_f / records),
          "repeatClients" => info.count { |_, a| a["records"] >= 2 },
          "moneyTotals" => money_totals,
          "monthly" => monthly,
          "returns" => [ 30, 60, 90 ].map { |days| { "days" => days }.merge(ret.(info, "return#{days}")) },
          "directions" => services.to_a.sort { |a, b| (b[1] <=> a[1]).nonzero? || (model.locale_key(a[0]) <=> model.locale_key(b[0])) }
            .first(12).map { |label, count| { "label" => label, "records" => count } },
          "sources" => [
            { "label" => "YCLIENTS", "records" => info.select { |c, _| c.key.start_with?("yclients:") }.sum { |_, a| a["records"] } },
            { "label" => "Другие источники", "records" => info.reject { |c, _| c.key.start_with?("yclients:") }.sum { |_, a| a["records"] } }
          ].select { |r| r["records"] > 0 },
          "frequency" => [
            bucket.("Нет состоявшихся", ->(a) { a["records"].zero? }),
            bucket.("1 обращение", ->(a) { a["records"] == 1 }),
            bucket.("2 обращения", ->(a) { a["records"] == 2 }),
            bucket.("3–5 обращений", ->(a) { a["records"].between?(3, 5) }),
            bucket.("6 и более", ->(a) { a["records"] >= 6 })
          ].select { |r| r["clients"] > 0 || r["label"] != "Нет состоявшихся" },
          "recency" => [
            bucket.("До 30 дней", ->(a) { !a["daysSince"].nil? && a["daysSince"] <= 30 }),
            bucket.("31–90 дней", ->(a) { since.(a, 30, 90) }),
            bucket.("91–180 дней", ->(a) { since.(a, 90, 180) }),
            bucket.("181–365 дней", ->(a) { since.(a, 180, 365) }),
            bucket.("Больше года", ->(a) { since.(a, 365, nil) })
          ],
          "life" => AnalyticsModel::LIFE.map do |l|
            xs = info.select { |_, a| a["lifecycle"] == l["id"] }
            { "id" => l["id"], "label" => l["label"], "clients" => xs.length, "costCents" => xs.sum { |_, a| a["cost"] || 0 } }
          end,
          "cohorts" => cohort_map.sort_by { |month, _| month }.map do |month, xs|
            {
              "month" => month, "clients" => xs.length, "r30" => ret.(xs, "return30"), "r60" => ret.(xs, "return60"),
              "r90" => ret.(xs, "return90"), "cost" => xs.sum { |_, a| a["cost"] || 0 },
              "windows" => Array.new(7) do |i|
                eligible = xs.select { |_, a| (a["tenureDays"] || -1) >= i * 30 + 29 }
                active = eligible.select do |c, _|
                  dates = visits.(c).map { |r| str(r["date"]) }
                  first = model.day(dates.first)
                  dates.any? { |d| model.day(d) - first >= i * 30 && model.day(d) - first <= i * 30 + 29 }
                end
                { "active" => active.length, "eligible" => eligible.length }
              end
            }
          end,
          "matrix" => %w[A B C N].flat_map do |a_class|
            %w[X Y Z].map do |z_class|
              xs = info.select { |_, a| a["abc"] == a_class && a["xyz"] == z_class }
              { "abc" => a_class, "xyz" => z_class, "clients" => xs.length, "costCents" => xs.sum { |_, a| a["cost"] || 0 } }
            end
          end
        }
      end

      # doctors: directory + history groups outside it
      directory = Doctor.order(:name, :id).pluck(:id, :name, :specialty)
      known = directory.map(&:first).to_set
      stats = {}
      cards.each do |c|
        visits.(c).each do |r|
          id = r["doctorId"].is_a?(String) && known.include?(r["doctorId"]) ? r["doctorId"] : "history:#{str(r['doctor']).strip.presence || 'Не указан'}"
          s = stats[id] ||= { name: str(r["doctor"]).strip.presence || "Врач не указан", keys: Set.new, records: 0, last_date: nil, services: Hash.new(0) }
          s[:keys] << c.key
          s[:records] += 1
          s[:last_date] = str(r["date"]) if s[:last_date].nil? || str(r["date"]) > s[:last_date]
          title = str(r["service"]).strip
          s[:services][title] += 1 if title.present?
        end
      end
      doctor_row = lambda do |id, name, specialty, in_directory|
        s = stats[id]
        {
          "id" => id, "name" => name, "specialty" => specialty,
          "directions" => (s ? s[:services].to_a : []).sort { |a, b| (b[1] <=> a[1]).nonzero? || (model.locale_key(a[0]) <=> model.locale_key(b[0])) }.first(5).map(&:first),
          "clientKeys" => (s ? s[:keys].to_a : []).sort,
          "completedRecords" => s ? s[:records] : 0, "lastDate" => s&.dig(:last_date), "inDirectory" => in_directory
        }
      end
      doctor_list = (directory.map { |id, name, specialty| doctor_row.(id, name, specialty, true) } +
        stats.keys.select { |id| id.start_with?("history:") }.sort.map { |id| doctor_row.(id, stats[id][:name], "", false) })
        .sort { |a, b| (b["completedRecords"] <=> a["completedRecords"]).nonzero? || (model.locale_key(a["name"]) <=> model.locale_key(b["name"])).nonzero? || (a["id"] <=> b["id"]) }

      # Records without a client card, as counted by the latest YCLIENTS calendar import.
      last_counts = LegacyImport.where("id LIKE ?", "yclients-calendar:%").order(imported_at: :desc).limit(1).pick(:counts)
      run_source = last_counts.is_a?(Hash) ? last_counts["source"] : nil
      anonymous_excluded = run_source ? (run_source["recordsWithoutClient"] || 0) + (run_source["recordsClientWithoutCard"] || 0) : 0

      attended_cards = cards.select { |c| per_card[c.key]["records"] > 0 }
      body = {
        "clients" => { "cutoff" => cutoff, "provenance" => "Проекция PostgreSQL: исторические карточки legacy_client_records и канонические контакты; оплаты CRM отдельно", "cardCount" => cards.length },
        "doctors" => { "cutoff" => cutoff, "doctors" => doctor_list },
        "analytics" => { "cutoff" => cutoff, "method" => METHOD, "source" => { "anonymousExcluded" => anonymous_excluded, "cards" => cards.length },
                         "perCard" => per_card, "scopes" => { "all" => scope.(cards), "attended" => scope.(attended_cards) } }
      }
      # One shared, content-derived batch: rebuilding unchanged data keeps the batch.
      batch_id = "pg-#{cutoff}-#{Json.sha256(Json.canonical(body))[0, 12]}"
      docs = KEYS.to_h { |k| [ k, { "batchId" => batch_id }.merge(body[k]) ] }
      {
        docs:,
        counts: {
          "batchId" => batch_id, "cutoff" => cutoff, "cards" => cards.length,
          "yclientsCards" => cards.count { |c| c.key.start_with?("yclients:") },
          "unnormalizedYclientsCards" => cards.count { |c| c.key.start_with?("yclients:") && c.payload["cardFormat"] != Yclients::CardFormat::VERSION },
          "attendingCards" => attended_cards.length, "completedVisits" => body["analytics"]["scopes"]["all"]["records"],
          "doctorsInDirectory" => directory.length, "doctorGroupsOutsideDirectory" => doctor_list.length - directory.length,
          "anonymousExcluded" => anonymous_excluded
        }
      }
    end

    def existing_docs
      FullCrmDocument.where(key: KEYS).pluck(:key, :data).to_h
    end

    def compare(existing, docs)
      KEYS.to_h do |k|
        state = if !existing.key?(k) then "absent"
        elsif Json.canonical(existing[k]) == Json.canonical(docs[k]) then "same"
        else "differs"
        end
        [ k, state ]
      end
    end

    def dry_run(cutoff: nil, preview_normalized: false)
      Calendar::Service.read_only do
        built = build(cutoff:, preview_normalized:)
        built[:counts].merge("documents" => compare(existing_docs, built[:docs]))
      end
    end

    # Writes all three documents in one transaction. Different stored documents are replaced
    # only with replace: true; otherwise nothing is written.
    def apply(cutoff: nil, replace: false)
      ActiveRecord::Base.transaction do
        Leads::Intake.advisory_lock(LOCK)
        built = build(cutoff:)
        if built[:counts]["unnormalizedYclientsCards"].positive?
          raise ProjectionError, "#{built[:counts]['unnormalizedYclientsCards']} YCLIENTS cards are not normalized; run yclients:normalize_cards APPLY=1 first"
        end
        state = compare(existing_docs, built[:docs])
        raise ProjectionError, "Stored workspace documents differ; rerun with REPLACE=1 to overwrite derived data" if !replace && state.values.include?("differs")
        KEYS.each do |key|
          next if state[key] == "same"
          FullCrmDocument.upsert({ key:, data: built[:docs][key] }, unique_by: :key)
        end
        raise "Projection readback mismatch" if compare(existing_docs, built[:docs]).values.any? { |s| s != "same" }
        run_id = "full-crm-projections:#{Json.iso(Time.current)}:#{SecureRandom.uuid}"
        LegacyImport.raw_insert_all([ { "id" => run_id, "hash" => built[:counts]["batchId"], "manifest" => { "keys" => KEYS },
                                       "archive" => { "kind" => "full-crm-projections", "before" => state }, "counts" => built[:counts] } ])
        { "runId" => run_id }.merge(built[:counts]).merge("documents" => state)
      end
    end
  end
end
