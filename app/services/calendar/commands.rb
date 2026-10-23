module Calendar
  # POST /api/crm/calendar body: { operation, operationId, expectedRevision, payload }.
  module Commands
    extend Validation::Check

    OPERATIONS = %w[add_doctor upsert_service add_interval remove_interval create_booking
                    reschedule_booking set_attendance record_payment cancel_booking].freeze
    ATTENDANCE = %w[scheduled confirmed arrived completed no_show].freeze
    METHODS = %w[cash card transfer].freeze

    module_function

    def parse(body)
      object(body, %w[operation operationId expectedRevision payload])
      operation = enum(body["operation"], OPERATIONS)
      {
        "operation" => operation,
        "operationId" => uuid(body["operationId"]),
        "expectedRevision" => int(body["expectedRevision"], min: 0),
        "payload" => payload(operation, body.fetch("payload") { fail! })
      }
    rescue Validation::Invalid
      nil
    end

    def payload(operation, p)
      case operation
      when "add_doctor"
        object(p, %w[name specialty])
        { "name" => string(p["name"], min: 1, max: 200, trim: true), "specialty" => string(p["specialty"], max: 200, trim: true) }
      when "upsert_service"
        object(p, %w[id doctorId title durationMinutes priceCents prepaymentPercent])
        fail! unless p.key?("priceCents")
        out = {}
        out["id"] = uuid(p["id"]) if p.key?("id")
        out.merge(
          "doctorId" => uuid(p["doctorId"]),
          "title" => string(p["title"], min: 1, max: 250, trim: true),
          "durationMinutes" => int(p["durationMinutes"], min: 5, max: 480),
          "priceCents" => nullable_int(p["priceCents"], min: 0, max: Validation::Check::INT_MAX),
          "prepaymentPercent" => int(p["prepaymentPercent"], min: 0, max: 100)
        )
      when "add_interval"
        object(p, %w[doctorId day from to kind])
        { "doctorId" => uuid(p["doctorId"]), "day" => day(p["day"]), "from" => minute(p["from"]),
          "to" => minute(p["to"]), "kind" => enum(p["kind"], %w[shift break]) }
      when "remove_interval"
        object(p, %w[id])
        { "id" => uuid(p["id"]) }
      when "create_booking"
        object(p, %w[patientId serviceId start note])
        { "patientId" => uuid(p["patientId"]), "serviceId" => uuid(p["serviceId"]),
          "start" => iso_datetime(p["start"]), "note" => note(p) }
      when "reschedule_booking"
        object(p, %w[id expectedVersion serviceId start note])
        { "id" => uuid(p["id"]), "expectedVersion" => int(p["expectedVersion"], min: 1),
          "serviceId" => uuid(p["serviceId"]), "start" => iso_datetime(p["start"]), "note" => note(p) }
      when "set_attendance"
        object(p, %w[id expectedVersion attendance])
        { "id" => uuid(p["id"]), "expectedVersion" => int(p["expectedVersion"], min: 1),
          "attendance" => enum(p["attendance"], ATTENDANCE) }
      when "record_payment"
        object(p, %w[id expectedVersion amountCents method note])
        { "id" => uuid(p["id"]), "expectedVersion" => int(p["expectedVersion"], min: 1),
          "amountCents" => int(p["amountCents"], min: 1, max: Validation::Check::INT_MAX), "method" => enum(p["method"], METHODS),
          "note" => p.key?("note") ? string(p["note"], max: 1000) : "" }
      when "cancel_booking"
        object(p, %w[id expectedVersion reason])
        { "id" => uuid(p["id"]), "expectedVersion" => int(p["expectedVersion"], min: 1),
          "reason" => string(p["reason"], max: 4000) }
      end
    end

    def note(p)
      p.key?("note") ? string(p["note"], max: 4000) : ""
    end
  end
end
