module Booking
  # Public booking from the quiz: catalog, free slots and one reservation per lead.
  module Service
    module_function

    # Service/doctor ids from the quiz may be source ids of the old local catalog.
    def resolve_id(kind, value)
      return nil unless value.is_a?(String) && value.length.between?(1, 128)
      CryptoHelpers.uuid?(value) ? value : CryptoHelpers.legacy_id(kind, value)
    end

    def parse_command(body)
      return nil unless body.is_a?(Hash) && (body.keys - %w[operationId leadId bookingToken serviceId start]).empty?
      check = Validation::Check
      {
        "operationId" => check.uuid(body["operationId"]),
        "leadId" => check.uuid(body["leadId"]),
        "bookingToken" => body["bookingToken"].is_a?(String) && body["bookingToken"].match?(/\A[a-f0-9]{64}\z/) ? body["bookingToken"] : check.fail!,
        "serviceId" => resolve_id("service", body["serviceId"]) || check.fail!,
        "start" => check.iso_datetime(body["start"])
      }
    rescue Validation::Invalid
      nil
    end

    def catalog
      {
        "timezone" => "Europe/Moscow",
        "doctors" => Doctor.order(:name, :id).pluck(:id, :name, :specialty).map { |id, name, specialty| { "id" => id, "name" => name, "specialty" => specialty } },
        "services" => DoctorService.order(:title, :id)
          .pluck(:id, :doctor_id, :title, :duration_minutes, :price_cents, :prepayment_percent)
          .map { |values| %w[id doctorId title durationMinutes priceCents prepaymentPercent].zip(values).to_h }
      }
    end

    def admit_public_read
      ActiveRecord::Base.transaction do
        quota = Leads::Throttle.admit(nil, secret: AppEnv.server.auth_secret, ip_max: 100, global_max: 1200,
                                           window_minutes: 1, namespace: "booking-read")
        raise Error.new(429, "too_many_requests") if quota.limited
      end
    end

    def book(command)
      ActiveRecord::Base.transaction do
        state = Calendar::Service.lock_calendar
        raise Error.new(403, "invalid_receipt") unless Receipt.valid?(command["leadId"], command["bookingToken"])
        lead = Lead.lock("FOR SHARE").find_by(id: command["leadId"])
        raise Error.new(403, "invalid_receipt") if lead.nil? || lead.status == "SPAM"
        # Never store the bearer token, even in the idempotency ledger.
        hash = Json.sha256(JSON.generate(command.except("bookingToken")))
        old = BookingOperation.find_by(id: command["operationId"])
        if old
          stored = BookingOperation.content_hash_of(id: old.id)
          raise Calendar::Error.new(409, "idempotency_conflict") if old.lead_id != command["leadId"] || stored != hash
          next old.result
        end
        quota = Leads::Throttle.admit(nil, secret: AppEnv.server.auth_secret, ip_max: 30, global_max: 300,
                                           window_minutes: 1, namespace: "booking")
        raise Error.new(429, "too_many_requests") if quota.limited
        raise Calendar::Error.new(409, "already_booked") if Appointment.where(lead_id: lead.id, status: "active").exists?

        conditions = Calendar::Service.check_slot!(command["serviceId"], command["start"])
        appointment = Appointment.create!(id: SecureRandom.uuid, lead_id: lead.id, patient_id: lead.patient_id,
                                          client_id: lead.client_id, **conditions)
        doctor = Doctor.find(conditions[:doctor_id])
        result = {
          "accepted" => true,
          "booking" => {
            "id" => appointment.id, "doctor" => doctor.name, "title" => conditions[:title],
            "start" => Json.iso(conditions[:start_at]), "end" => Json.iso(conditions[:end_at]),
            "priceCents" => conditions[:price_cents], "prepaymentPercent" => conditions[:prepayment_percent],
            "paymentConfirmed" => false
          }
        }
        AuditLog.write!(actor: "system", entity: "appointment", entity_id: appointment.id, action: "appointment.created",
                        after: Json.row(appointment.reload).merge("origin" => "quiz"))
        state.update_columns(revision: state.revision + 1)
        BookingOperation.raw_insert_all([ { "id" => command["operationId"], "lead_id" => lead.id, "hash" => hash, "result" => result } ])
        result
      end
    end
  end
end
