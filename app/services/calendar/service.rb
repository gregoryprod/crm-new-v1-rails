module Calendar
  # Clinic calendar: catalog, shifts/breaks, bookings and payments. Every write takes one
  # clinic-wide lock (calendar_state row) and rechecks availability inside it; the database
  # exclusion constraint on appointments is the final guard against double booking.
  module Service
    TIMEZONE = "Europe/Moscow"
    TRANSITIONS = {
      "scheduled" => %w[confirmed arrived no_show],
      "confirmed" => %w[scheduled arrived no_show],
      "arrived" => %w[completed]
    }.freeze

    module_function

    def missing = Error.new(404, "not_found")
    def conflict = Error.new(409, "calendar_conflict")

    def find_service!(id)
      DoctorService.find_by(id:) || raise(missing)
    end

    # The bookable slot for `service_id` starting at `value`, or slot_unavailable.
    def check_slot!(service_id, value, exclude_id = nil)
      selected = find_service!(service_id)
      start = Time.iso8601(value).utc
      day = Slots.moscow_day(start)
      inputs = slot_inputs(selected.doctor_id, day, selected.duration_minutes, exclude_id)
      available = Slots.available(inputs[:shifts], inputs[:blocked], day, selected.duration_minutes)
      raise Error.new(409, "slot_unavailable") unless available.any? { |slot| slot["start"] == Json.iso(start) }
      {
        doctor_id: selected.doctor_id, service_id: selected.id, title: selected.title,
        price_cents: selected.price_cents, prepayment_percent: selected.prepayment_percent,
        start_at: start, end_at: start + selected.duration_minutes * 60
      }
    end

    def intervals_in(range, doctor_id = nil)
      scope = CalendarInterval.where("start_at < ? AND end_at > ?", range.end, range.start)
      doctor_id ? scope.where(doctor_id:) : scope
    end

    def slot_inputs(doctor_id, day, duration, exclude_id = nil)
      range = Slots.day_range(day)
      finish = range.end + duration * 60
      intervals = intervals_in(Slots::Range.new(start: range.start, end: finish), doctor_id).to_a
      booked = Appointment.where(doctor_id:, status: "active").where("start_at < ? AND end_at > ?", finish, range.start)
      booked = booked.where.not(id: exclude_id) if exclude_id
      {
        shifts: intervals.select { |i| i.kind == "shift" },
        blocked: intervals.select { |i| i.kind == "break" } + booked.to_a
      }
    end

    BOOKING_SQL = <<~SQL.freeze
      SELECT a.id, a.lead_id, a.doctor_id, a.service_id, a.patient_id, a.client_id, a.title,
             a.start_at, a.end_at, a.status, a.attendance, a.version, a.note, a.price_cents,
             a.prepayment_percent, a.cancellation_reason,
             c.last_name AS client_name, c.first_name AS client_first_name,
             p.name AS patient_name, p.species
      FROM appointments a
      JOIN clients c ON c.id = a.client_id
      JOIN patients p ON p.id = a.patient_id
    SQL
    BOOKING_KEYS = %w[id leadId doctorId serviceId patientId clientId title start end status attendance
                      version note priceCents prepaymentPercent cancellationReason clientName
                      clientFirstName patientName species].freeze

    def booking_rows(where, *binds)
      sql = ApplicationRecord.sql("#{BOOKING_SQL} WHERE #{where} ORDER BY a.start_at, a.id", *binds)
      ActiveRecord::Base.connection.select_all(sql).cast_values.map { |values| BOOKING_KEYS.zip(values).to_h }
    end

    def booking_by_id(id)
      booking_rows("a.id = ?", id).first
    end

    def bookings_in(range, doctor_id = nil)
      return booking_rows("a.start_at < ? AND a.end_at > ? AND a.doctor_id = ?", range.end, range.start, doctor_id) if doctor_id
      booking_rows("a.start_at < ? AND a.end_at > ?", range.end, range.start)
    end

    def catalog
      {
        "doctors" => Doctor.order(:name, :id).map { |d| Json.row(d) },
        "services" => DoctorService.order(:title, :id).map { |s| Json.row(s) }
      }
    end

    def read_only
      ActiveRecord::Base.transaction(isolation: :repeatable_read) do
        ActiveRecord::Base.connection.execute("SET TRANSACTION READ ONLY")
        yield
      end
    end

    def snapshot(day:, view:, doctor_id: nil)
      read_only do
        range = Slots.day_range(day, view == "week" ? 7 : 1)
        bookings = bookings_in(range, doctor_id)
        ids = bookings.map { |b| b["id"] }
        receipts = ids.any? ? Payment.where(booking_id: ids).map { |p| Json.row(p) } : []
        history = ids.any? ? appointment_history(ids) : []
        {
          "revision" => CalendarState.where(id: 1).pick(:revision) || 0,
          "timezone" => TIMEZONE,
          **catalog,
          "intervals" => intervals_in(range, doctor_id).map { |i| Json.row(i) },
          "bookings" => bookings,
          "payments" => receipts,
          "history" => history
        }
      end
    end

    def appointment_history(ids)
      sql = ApplicationRecord.sql(<<~SQL, ids)
        SELECT l.id, l.entity_id, l.actor, u.name, l.action, l.before, l.after, l.at
        FROM audit_log l LEFT JOIN users u ON l.actor = u.id::text
        WHERE l.entity = 'appointment' AND l.entity_id IN (?)
        ORDER BY l.at DESC LIMIT 200
      SQL
      ActiveRecord::Base.connection.select_all(sql).cast_values.map do |values|
        %w[id entityId actor actorName action before after at].zip(values).to_h
      end
    end

    def slots(day:, service_id:, exclude_id: nil)
      read_only do
        selected = find_service!(service_id)
        if exclude_id
          appointment = Appointment.find_by(id: exclude_id)
          raise missing if appointment.nil? || appointment.status != "active"
        end
        input = slot_inputs(selected.doctor_id, day, selected.duration_minutes, exclude_id)
        { "timezone" => TIMEZONE, "slots" => Slots.available(input[:shifts], input[:blocked], day, selected.duration_minutes) }
      end
    end

    def lock_calendar
      ActiveRecord::Base.connection.execute("INSERT INTO calendar_state (id, revision) VALUES (1, 0) ON CONFLICT DO NOTHING")
      CalendarState.lock.find(1)
    end

    def active_overlap?(doctor_id, start_at, end_at)
      Appointment.where(doctor_id:, status: "active").where("start_at < ? AND end_at > ?", end_at, start_at).exists?
    end

    def execute(actor_id, command)
      ActiveRecord::Base.transaction do
        # One clinic-wide write lock covers schedule edits as well as booking writes.
        # Checking availability before taking this lock would allow double booking.
        state = lock_calendar
        hash = Json.sha256(JSON.generate(command))
        old = CalendarOperation.find_by(id: command["operationId"])
        if old
          raise conflict if old.actor_id != actor_id || CalendarOperation.content_hash_of(id: old.id) != hash
          next old.result
        end
        raise conflict if state.revision != command["expectedRevision"]

        p = command["payload"]
        audit = ->(entity, id, action, before, after) do
          AuditLog.write!(actor: actor_id, entity:, entity_id: id, action:, before:, after:)
        end
        id = case command["operation"]
        when "add_doctor"
          doctor = Doctor.create!(id: SecureRandom.uuid, name: p["name"], specialty: p["specialty"])
          audit.("doctor", doctor.id, "doctor.created", nil, p)
          doctor.id
        when "upsert_service"
          raise missing unless Doctor.exists?(id: p["doctorId"])
          service_id = p["id"] || SecureRandom.uuid
          before = DoctorService.find_by(id: service_id)
          raise missing if p["id"] && (before.nil? || before.doctor_id != p["doctorId"])
          values = { doctor_id: p["doctorId"], title: p["title"], duration_minutes: p["durationMinutes"],
                     price_cents: p["priceCents"], prepayment_percent: p["prepaymentPercent"] }
          before_row = before && Json.row(before)
          before ? before.update!(values) : DoctorService.create!(values.merge(id: service_id))
          audit.("service", service_id, before ? "service.updated" : "service.created", before_row, p)
          service_id
        when "add_interval"
          raise missing unless Doctor.exists?(id: p["doctorId"])
          start_at = Time.iso8601("#{p['day']}T#{p['from']}:00#{Slots::OFFSET}").utc
          end_at = Time.iso8601("#{p['day']}T#{p['to']}:00#{Slots::OFFSET}").utc
          raise Error.new(400, "invalid_interval") if start_at >= end_at
          range = Slots::Range.new(start: start_at, end: end_at)
          if p["kind"] == "shift"
            raise conflict if intervals_in(range, p["doctorId"]).any? { |i| i.kind == "shift" && Slots.overlaps?(i, range) }
          elsif active_overlap?(p["doctorId"], start_at, end_at)
            raise Error.new(409, "occupied_interval")
          end
          interval = CalendarInterval.create!(id: SecureRandom.uuid, doctor_id: p["doctorId"], kind: p["kind"], start_at:, end_at:)
          audit.("calendar_interval", interval.id, "interval.created", nil, p.merge("start" => start_at, "end" => end_at))
          interval.id
        when "remove_interval"
          before = CalendarInterval.find_by(id: p["id"]) || raise(missing)
          raise Error.new(409, "occupied_interval") if before.kind == "shift" && active_overlap?(before.doctor_id, before.start_at, before.end_at)
          before_row = Json.row(before)
          before.delete
          audit.("calendar_interval", before.id, "interval.removed", before_row, nil)
          before.id
        when "create_booking"
          patient = Patient.lock("FOR SHARE").find_by(id: p["patientId"]) || raise(missing)
          conditions = check_slot!(p["serviceId"], p["start"])
          appointment = Appointment.create!(id: SecureRandom.uuid, patient_id: patient.id, client_id: patient.client_id,
                                            note: p["note"], **conditions)
          audit.("appointment", appointment.id, "appointment.created", nil, Json.row(appointment.reload))
          appointment.id
        when "reschedule_booking"
          before = Appointment.lock.find_by(id: p["id"]) || raise(missing)
          raise conflict if before.status != "active" || before.version != p["expectedVersion"] || !%w[scheduled confirmed].include?(before.attendance)
          before_row = Json.row(before)
          conditions = check_slot!(p["serviceId"], p["start"], before.id)
          before.update!(conditions.merge(note: p["note"], version: before.version + 1))
          audit.("appointment", before.id, "appointment.rescheduled", before_row, Json.row(before.reload))
          before.id
        when "set_attendance"
          before = Appointment.lock.find_by(id: p["id"]) || raise(missing)
          raise conflict if before.status != "active" || before.version != p["expectedVersion"]
          raise Error.new(409, "invalid_attendance_transition") unless TRANSITIONS.fetch(before.attendance, []).include?(p["attendance"])
          if %w[completed no_show].include?(p["attendance"]) && before.start_at > Time.current
            raise Error.new(409, "appointment_not_started")
          end
          before_row = Json.row(before)
          before.update!(attendance: p["attendance"], version: before.version + 1)
          audit.("appointment", before.id, "appointment.attendance_changed", before_row, Json.row(before.reload))
          before.id
        when "record_payment"
          before = Appointment.lock.find_by(id: p["id"]) || raise(missing)
          raise conflict if before.status != "active" || before.attendance != "completed" || before.version != p["expectedVersion"]
          raise Error.new(409, "payment_already_recorded") if Payment.exists?(booking_id: before.id)
          payment = Payment.create!(booking_id: before.id, client_id: before.client_id, patient_id: before.patient_id,
                                    doctor_id: before.doctor_id, service_id: before.service_id, title: before.title,
                                    amount_cents: p["amountCents"], method: p["method"], actor_id:, note: p["note"])
          before.update!(version: before.version + 1)
          audit.("appointment", before.id, "appointment.payment_recorded", nil, Json.row(payment.reload))
          before.id
        when "cancel_booking"
          before = Appointment.lock.find_by(id: p["id"]) || raise(missing)
          raise conflict if before.status != "active" || before.version != p["expectedVersion"] || !%w[scheduled confirmed].include?(before.attendance)
          before_row = Json.row(before)
          before.update!(status: "cancelled", cancellation_reason: p["reason"], version: before.version + 1)
          audit.("appointment", before.id, "appointment.cancelled", before_row, Json.row(before.reload))
          before.id
        end

        result = { "saved" => true, "revision" => state.revision + 1, "id" => id }
        state.update_columns(revision: result["revision"])
        CalendarOperation.raw_insert_all([ { "id" => command["operationId"], "actor_id" => actor_id, "hash" => hash, "result" => result } ])
        result
      end
    end
  end
end
