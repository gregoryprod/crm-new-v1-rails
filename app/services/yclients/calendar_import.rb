module Yclients
  # Insert-only import of YCLIENTS visits, future records and doctors' working schedule into
  # the CRM calendar. Every row gets a deterministic id derived from the YCLIENTS id, so
  # re-running the same or an overlapping export never duplicates anything, and rows that
  # already exist are never updated: staff edits in the CRM always win. Rows created by an
  # earlier run and later removed in the CRM are not recreated.
  module CalendarImport
    RUN_PREFIX = "yclients-calendar:"
    LOCK = "vpc-yclients-calendar-import"
    MOSCOW = "+03:00"
    DAY = 86_400
    UNKNOWN_PET_NAME = "Имя не указано"
    UNKNOWN_SPECIES = "Не указан"
    FALLBACK_TITLE = "Запись YCLIENTS"
    PET_NOTE = "Создан импортом YCLIENTS из поля «Кличка питомца» (решение владельца 17.10.2026, issue #22); вид в источнике не указан."
    TIME = /\A([01]\d|2[0-4]):[0-5]\d\z/

    Range = Calendar::Slots::Range

    module Ids
      module_function

      def id(kind, value) = CryptoHelpers.legacy_id(kind, value)
      def appointment(record_id) = id("yclients-record", record_id.to_s)
      def break_interval(record_id) = id("yclients-break", record_id.to_s)
      def shift(staff_id, date, from, to) = id("yclients-shift", "#{staff_id}:#{date}:#{from}-#{to}")
      def patient(client_id) = id("yclients-patient", client_id.to_s)
      def client(client_id) = id("client", client_id.to_s)
      def doctor(staff_id) = id("doctor", staff_id.to_s)
      def service(service_id, staff_id) = id("service", "#{service_id}:#{staff_id}")
      def fallback_service(staff_id, service_ids, minutes) = id("yclients-service", "#{staff_id}:#{service_ids.empty? ? 'none' : service_ids.join('+')}:#{minutes}")
      def audit(record_id) = id("yclients-audit", record_id.to_s)
    end

    module_function

    # YCLIENTS attendance: -1 no-show, 0 waiting, 1 arrived, 2 confirmed; deleted → cancelled.
    def map_status(r, finish, now)
      return { status: "cancelled", attendance: "scheduled" } if r.deleted
      case r.attendance
      when 1 then { status: "active", attendance: finish <= now ? "completed" : "arrived" }
      when -1 then { status: "active", attendance: "no_show" }
      when 2 then { status: "active", attendance: "confirmed" }
      else { status: "active", attendance: "scheduled" }
      end
    end

    def parse_time(iso)
      Time.iso8601(iso).utc
    rescue ArgumentError
      begin
        Time.strptime(iso, "%Y-%m-%dT%H:%M:%S%z").utc
      rescue ArgumentError
        nil
      end
    end

    def record_range(r)
      iso = r.datetime.presence || (r.date.present? ? r.date.sub(" ", "T") : "")
      iso += MOSCOW if iso.present? && !iso.match?(/(Z|[+-]\d{2}:?\d{2})\z/i)
      start = iso.present? ? parse_time(iso) : nil
      seconds = r.length || r.seance_length || 0
      return nil if start.nil? || !(seconds > 0) || seconds > DAY
      Range.new(start:, end: start + seconds)
    end

    def slot_range(date, from, to)
      return nil unless date.match?(/\A\d{4}-\d{2}-\d{2}\z/) && TIME.match?(from) && TIME.match?(to)
      start = parse_time("#{date}T#{from}:00#{MOSCOW}")
      finish = to == "24:00" ? parse_time("#{date}T00:00:00#{MOSCOW}")&.+(DAY) : parse_time("#{date}T#{to}:00#{MOSCOW}")
      finish += DAY if finish && to == "00:00"
      return nil if start.nil? || finish.nil? || start >= finish
      Range.new(start:, end: finish)
    end

    def overlaps?(a, b) = Calendar::Slots.overlaps?(a, b)

    def empty_counts(source)
      {
        "source" => source.stats,
        "appointments" => { "new" => 0, "existing" => 0, "newByStatus" => {}, "skipped" => {} },
        "breaks" => { "new" => 0, "existing" => 0, "skipped" => {} },
        "shifts" => { "new" => 0, "existing" => 0, "skipped" => {} },
        "clients" => { "new" => 0, "existing" => 0 },
        "patients" => { "new" => 0, "existing" => 0 },
        "services" => { "matched" => 0, "new" => 0, "existingFallback" => 0 },
        # YCLIENTS record ids only (no personal data) so an operator can check them in YCLIENTS.
        "skippedRecordIds" => {}
      }
    end

    def service_minutes(range)
      [ 480, [ 5, ((range.end - range.start) / 60.0 + 0.5).floor ].max ].min
    end

    def fallback_service_id(r, range)
      Ids.fallback_service(r.staff_id, r.services.map { |s| s["id"] }, service_minutes(range))
    end

    def chunked_ids(model, column, values, extra = nil)
      values.each_slice(500).flat_map do |part|
        scope = model.where(column => part)
        scope = extra.call(scope) if extra
        scope.pluck(column)
      end
    end

    # Reads the destination and decides, without writing, what the import would create.
    def plan(source, now)
      counts = empty_counts(source)
      bump = ->(bucket, key) { bucket[key] = (bucket[key] || 0) + 1 }
      skip = lambda do |bucket, reason, record_id = nil|
        bump.(bucket, reason)
        (counts["skippedRecordIds"][reason] ||= []) << record_id unless record_id.nil?
      end

      # what earlier runs created (so rows removed in the CRM are not recreated)
      imported = Set.new
      LegacyImport.where("id LIKE ?", "#{RUN_PREFIX}%").pluck(:archive).each do |archive|
        created = archive.is_a?(Hash) ? archive["created"] : nil
        next unless created.is_a?(Hash)
        created.each_value { |list| list.each { |id| imported << id if id.is_a?(String) } if list.is_a?(Array) }
      end

      staff_ids = (source.records.map(&:staff_id) + source.schedule.map(&:staff_id)).uniq
      known_doctors = chunked_ids(Doctor, :id, staff_ids.map { |id| Ids.doctor(id) }).to_set

      client_ids = source.records.filter_map { |r| r.client&.dig("id") }.uniq
      linked = client_ids.map { |id| "yclients:#{id}" }.each_slice(500).flat_map do |part|
        LegacyClientRecord.where(source_key: part).pluck(:source_key, :client_id)
      end.to_h
      bare = chunked_ids(Client, :id, client_ids.map { |id| Ids.client(id) }).to_set
      crm_client = {}
      client_ids.each do |id|
        existing = linked["yclients:#{id}"] || (bare.include?(Ids.client(id)) ? Ids.client(id) : nil)
        crm_client[id] = existing if existing
      end
      existing_clients = crm_client.size
      records_by_client = Hash.new { |h, k| h[k] = [] }
      source.records.each { |r| records_by_client[r.client["id"]] << r if r.client }

      existing_patients = crm_client.values.uniq.each_slice(500).flat_map do |part|
        Patient.where(client_id: part).pluck(:id, :client_id, :name)
      end

      ranges = source.records.to_h { |r| [ r.id, record_range(r) ] }
      candidates = Set.new
      source.records.each { |r| candidates << Ids.service(r.services.first["id"], r.staff_id) if r.services.length == 1 }
      source.records.each { |r| (range = ranges[r.id]) && candidates << fallback_service_id(r, range) }
      known_services = chunked_ids(DoctorService, :id, candidates.to_a).to_set

      existing_appointments = chunked_ids(Appointment, :id, source.records.map { |r| Ids.appointment(r.id) }).to_set
      slot_ranges = source.schedule.map { |s| slot_range(s.date, s.from, s.to) }
      all_ranges = (ranges.values + slot_ranges).compact
      window = if all_ranges.any?
        Range.new(start: all_ranges.map(&:start).min, end: all_ranges.map(&:end).max)
      else
        Range.new(start: now, end: now)
      end
      doctor_list = known_doctors.to_a
      active_busy = doctor_list.each_slice(500).flat_map do |part|
        Appointment.where(doctor_id: part, status: "active").where("start_at < ? AND end_at > ?", window.end, window.start)
          .pluck(:id, :doctor_id, :start_at, :end_at)
      end
      intervals = doctor_list.each_slice(500).flat_map do |part|
        CalendarInterval.where(doctor_id: part).where("start_at < ? AND end_at > ?", window.end, window.start).to_a
      end
      interval_ids = intervals.map(&:id).to_set
      busy = Hash.new { |h, k| h[k] = [] }
      active_busy.each { |_, doctor_id, s, e| busy[doctor_id] << Range.new(start: s, end: e) }
      shifts_by = Hash.new { |h, k| h[k] = [] }
      intervals.select { |i| i.kind == "shift" }.each { |i| shifts_by[i.doctor_id] << Range.new(start: i.start_at, end: i.end_at) }

      plan = { clients: [], patients: [], services: [], appointments: [], intervals: [], audit: [] }
      planned_services = Set.new
      patient_of = {}
      client_of = lambda do |yid|
        next crm_client[yid] if crm_client[yid]
        rows = Legacy::Rows.client_rows(Source.card(yid, records_by_client[yid], source.profiles[yid]))
        plan[:clients] << rows
        crm_client[yid] = rows[:client]["id"]
      end
      resolve_patient = lambda do |r, client_id|
        yid = r.client["id"]
        next patient_of[yid] if patient_of.key?(yid)
        profile = source.profiles[yid]
        pet_name = Source.custom_field(profile, Source::PET_NAME_FIELD) ||
          records_by_client[yid].map { |x| Source.custom_field(x.client, Source::PET_NAME_FIELD) }.find(&:itself)
        breed = Source.custom_field(profile, Source::PET_BREED_FIELD) ||
          records_by_client[yid].map { |x| Source.custom_field(x.client, Source::PET_BREED_FIELD) }.find(&:itself)
        name = pet_name || UNKNOWN_PET_NAME
        own = existing_patients.select { |_, owner, _| owner == client_id }
        reuse = own.find { |id, _, _| id == Ids.patient(yid) } || own.find { |_, _, n| n.to_s.strip.downcase == name.downcase }
        id = if reuse
          counts["patients"]["existing"] += 1
          reuse[0]
        elsif imported.include?(Ids.patient(yid))
          nil # imported earlier and removed in the CRM since: do not bring it back
        else
          plan[:patients] << { "id" => Ids.patient(yid), "client_id" => client_id, "species" => UNKNOWN_SPECIES,
                               "name" => name, "breed" => breed, "notes" => PET_NOTE }
          Ids.patient(yid)
        end
        patient_of[yid] = id
      end
      resolve_service = lambda do |r, range|
        doctor_id = Ids.doctor(r.staff_id)
        if r.services.length == 1
          matched = Ids.service(r.services.first["id"], r.staff_id)
          if known_services.include?(matched)
            counts["services"]["matched"] += 1
            next matched
          end
        end
        id = fallback_service_id(r, range)
        if known_services.include?(id)
          counts["services"]["existingFallback"] += 1
        elsif !planned_services.include?(id)
          planned_services << id
          plan[:services] << { "id" => id, "doctor_id" => doctor_id, "title" => Source.record_title(r).presence || FALLBACK_TITLE,
                               "duration_minutes" => service_minutes(range), "price_cents" => Source.record_cost_cents(r),
                               "prepayment_percent" => 0 }
        else
          counts["services"]["existingFallback"] += 1
        end
        id
      end

      ordered = source.records.sort_by { |r| [ ranges[r.id]&.start&.to_r || 0, r.id ] }
      ordered.each do |r|
        range = ranges[r.id]
        doctor_id = Ids.doctor(r.staff_id)
        if r.client_without_card
          # A named visitor without a YCLIENTS card: neither a break nor a guessable client.
          skip.(counts["appointments"]["skipped"], "client_without_yclients_card", r.id)
          next
        end
        unless r.client
          # Service blocks without a client: a doctor's break, never an appointment.
          id = Ids.break_interval(r.id)
          if r.deleted then skip.(counts["breaks"]["skipped"], "deleted_without_client")
          elsif !range then skip.(counts["breaks"]["skipped"], "invalid_time", r.id)
          elsif !known_doctors.include?(doctor_id) then skip.(counts["breaks"]["skipped"], "unknown_doctor", r.id)
          elsif interval_ids.include?(id) then counts["breaks"]["existing"] += 1
          elsif imported.include?(id) then skip.(counts["breaks"]["skipped"], "removed_in_crm", r.id)
          else
            plan[:intervals] << { "id" => id, "doctor_id" => doctor_id, "kind" => "break", "start_at" => range.start, "end_at" => range.end }
            counts["breaks"]["new"] += 1
          end
          next
        end
        id = Ids.appointment(r.id)
        next skip.(counts["appointments"]["skipped"], "invalid_time", r.id) unless range
        next skip.(counts["appointments"]["skipped"], "unknown_doctor", r.id) unless known_doctors.include?(doctor_id)
        if existing_appointments.include?(id)
          counts["appointments"]["existing"] += 1
          next
        end
        next skip.(counts["appointments"]["skipped"], "removed_in_crm", r.id) if imported.include?(id)
        # A cancelled record alone does not justify creating a new client card.
        if !crm_client.key?(r.client["id"]) && records_by_client[r.client["id"]].none? { |x| !x.deleted }
          next skip.(counts["appointments"]["skipped"], "cancelled_for_unknown_client", r.id)
        end
        status = map_status(r, range.end, now)
        taken = busy[doctor_id]
        # PostgreSQL forbids overlapping active appointments of one doctor.
        if status[:status] == "active" && taken.any? { |b| overlaps?(b, range) }
          next skip.(counts["appointments"]["skipped"], "overlaps_active_appointment", r.id)
        end
        client_id = client_of.(r.client["id"])
        patient_id = resolve_patient.(r, client_id)
        next skip.(counts["appointments"]["skipped"], "patient_removed_in_crm", r.id) unless patient_id
        taken << range if status[:status] == "active"
        service_id = resolve_service.(r, range)
        created_raw = r.create_date.include?("T") || r.create_date.empty? ? r.create_date : r.create_date.sub(" ", "T") + MOSCOW
        created = created_raw.empty? ? nil : parse_time(created_raw)
        row = {
          "id" => id, "doctor_id" => doctor_id, "service_id" => service_id, "client_id" => client_id, "patient_id" => patient_id,
          "title" => Source.record_title(r).presence || FALLBACK_TITLE, "price_cents" => Source.record_cost_cents(r),
          "prepayment_percent" => 0, "start_at" => range.start, "end_at" => range.end, "status" => status[:status],
          "attendance" => status[:attendance], "note" => [ "Импорт YCLIENTS, запись #{r.id}", r.comment ].reject(&:blank?).join("\n"),
          "cancellation_reason" => r.deleted ? "Удалена в YCLIENTS" : nil
        }
        row["created_at"] = created if created
        plan[:appointments] << row
        plan[:audit] << {
          "id" => Ids.audit(r.id), "actor" => "system", "entity" => "appointment", "entity_id" => id,
          "action" => "appointment.imported", "before" => nil,
          "after" => { "source" => "yclients", "recordId" => r.id, "attendance" => r.attendance, "deleted" => r.deleted,
                       "status" => status[:status], "mappedAttendance" => status[:attendance] }
        }
        counts["appointments"]["new"] += 1
        bump.(counts["appointments"]["newByStatus"], status[:status] == "cancelled" ? "cancelled" : status[:attendance])
      end

      source.schedule.each_with_index do |s, index|
        range = slot_ranges[index]
        doctor_id = Ids.doctor(s.staff_id)
        id = Ids.shift(s.staff_id, s.date, s.from, s.to)
        if !range then skip.(counts["shifts"]["skipped"], "invalid_time")
        elsif !known_doctors.include?(doctor_id) then skip.(counts["shifts"]["skipped"], "unknown_doctor")
        elsif interval_ids.include?(id) then counts["shifts"]["existing"] += 1
        elsif imported.include?(id) then skip.(counts["shifts"]["skipped"], "removed_in_crm")
        else
          taken = shifts_by[doctor_id]
          # The calendar never stores two overlapping shifts of one doctor.
          if taken.any? { |t| overlaps?(t, range) }
            skip.(counts["shifts"]["skipped"], "overlaps_existing_shift")
          else
            taken << range
            plan[:intervals] << { "id" => id, "doctor_id" => doctor_id, "kind" => "shift", "start_at" => range.start, "end_at" => range.end }
            counts["shifts"]["new"] += 1
          end
        end
      end
      counts["clients"]["new"] = plan[:clients].length
      counts["clients"]["existing"] = existing_clients
      counts["patients"]["new"] = plan[:patients].length
      counts["services"]["new"] = plan[:services].length
      { counts:, plan: }
    end

    # Dry run: one read-only snapshot, nothing is written.
    def dry_run(source, now = Time.current)
      Calendar::Service.read_only { plan(source, now)[:counts] }
    end

    def insert_all(model, rows, unique_by: nil)
      rows.each_slice(200).flat_map do |part|
        model.insert_all(part, returning: [ model.primary_key ], unique_by:).rows.flatten
      end
    end

    # Applies the plan in one transaction under the import lock and the calendar lock.
    def apply(source, now = Time.current)
      ActiveRecord::Base.transaction do
        Leads::Intake.advisory_lock(LOCK)
        # Same lock as manual calendar edits: no booking can slip in between plan and insert.
        state = Calendar::Service.lock_calendar
        result = plan(source, now)
        counts = result[:counts]
        plan = result[:plan]
        created = {}
        created["clients"] = plan[:clients].each_slice(200).flat_map do |part|
          ids = Client.insert_all(part.map { |p| p[:client] }, returning: [ :id ]).rows.flatten
          cards = LegacyClientRecord.raw_insert_all(part.map { |p| p[:record] }, returning: "source_id", on_conflict_do_nothing: true)
          # Every new client must get its source card, never a card of another client.
          raise "Import plan diverged from destination" if cards.length != part.length
          ids
        end
        created["patients"] = insert_all(Patient, plan[:patients])
        created["services"] = insert_all(DoctorService, plan[:services])
        created["appointments"] = insert_all(Appointment, plan[:appointments].map { |row| row.reverse_merge("created_at" => Time.current) })
        created["intervals"] = insert_all(CalendarInterval, plan[:intervals])
        insert_all(AuditLog, plan[:audit].map { |row| row.merge("at" => Time.current) })
        # The plan was made under both locks, so every planned row must have been inserted.
        %w[clients patients services appointments intervals].each do |key|
          raise "Import plan diverged from destination" if created[key].length != plan[key.to_sym].length
        end
        changed = created.values.any?(&:any?)
        # Open calendar tabs compare revisions; bump it so they reload the imported rows.
        revision = changed ? state.revision + 1 : state.revision
        state.update_columns(revision:) if changed
        run_id = "#{RUN_PREFIX}#{Json.iso(Time.current)}:#{SecureRandom.uuid}"
        LegacyImport.raw_insert_all([ { "id" => run_id, "hash" => source.digest, "manifest" => source.manifest,
                                        "archive" => { "kind" => "yclients-calendar", "created" => created }, "counts" => Json.plain(counts) } ])
        { "runId" => run_id, "revision" => revision, "counts" => counts }
      end
    end
  end
end
