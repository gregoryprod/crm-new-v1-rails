module FullCrm
  # JSON API of the restored workspace (public/full-crm): historical card projections plus
  # canonical PostgreSQL contacts, live appointments/payments, per-client work and stages.
  module Service
    STAGES = %w[unassigned contact doctor booking followup closed].freeze
    RESOURCES_WRITE = %w[client-work workflow].freeze
    EMPTY_PER_CARD = {
      "records" => 0, "uniqueDays" => 0, "cost" => nil, "averageCostCents" => nil, "daysSince" => nil, "tenureDays" => nil,
      "cohort" => nil, "lifecycle" => "no_visits", "xyz" => nil, "abc" => "?", "averageGapDays" => nil, "zeroCost" => 0,
      "deleted" => 0, "nonAttended" => 0, "doctors" => 0, "petNames" => [], "cost90Cents" => nil,
      "return30" => { "eligible" => false, "returned" => nil }, "return60" => { "eligible" => false, "returned" => nil },
      "return90" => { "eligible" => false, "returned" => nil }
    }.freeze

    Row = Data.define(:client, :source_id, :source_key, :payload)
    # zod 4 z.email()
    EMAIL = /\A(?!\.)(?!.*\.\.)([A-Za-z0-9_'+\-.]*)[A-Za-z0-9_+-]@([A-Za-z0-9][A-Za-z0-9\-]*\.)+[A-Za-z]{2,}\z/

    module_function

    def identity(include_payload: false)
      columns = [ "clients.id", "legacy_client_records.source_id", "legacy_client_records.source_key" ]
      columns << "legacy_client_records.payload" if include_payload
      clients = Client.all.index_by(&:id)
      Client.left_joins(:legacy_client_record).pluck(*columns).map do |id, source_id, source_key, payload|
        Row.new(client: clients[id], source_id:, source_key:, payload:)
      end
    end

    def documents(resource = "")
      keys = [ "clients" ] + (%w[analytics doctors].include?(resource) ? [ resource ] : [])
      FullCrmDocument.where(key: keys).pluck(:key, Arel.sql("CASE WHEN key = 'clients' THEN data - 'cards' ELSE data END"))
        .to_h { |key, data| [ key, data.is_a?(String) ? JSON.parse(data) : data ] }
    end

    def key_of(row) = row.source_key || row.client.id
    def source_of(row) = row.source_id || row.client.id
    def name_of(client) = [ client.last_name, client.first_name ].reject(&:blank?).join(" ")

    def profile_of(row)
      { "name" => name_of(row.client), "phone" => row.client.phone || row.client.phone_raw, "email" => row.client.email,
        "canonicalClientId" => row.client.id }
    end

    def snapshot(record, key, batch_id)
      { "batchId" => batch_id, "key" => key, "revision" => record["revision"], "owner" => record["owner"],
        "tasks" => record["tasks"], "comments" => record["comments"], "events" => record["events"],
        "updatedAt" => record["updatedAt"], "summary" => Work.summary(record) }
    end

    def finance(rows)
      key_by_id = rows.to_h { |r| [ r.client.id, key_of(r) ] }
      source_by_id = rows.to_h { |r| [ r.client.id, source_of(r) ] }
      doctors = Doctor.pluck(:id, :name).to_h
      clients = rows.to_h { |r| [ r.client.id, r.client ] }
      list = Payment.where(doctor_id: doctors.keys, client_id: clients.keys).map do |payment|
        Json.row(payment).merge(
          "paidAt" => Json.iso(payment.paid_at), "clientKey" => key_by_id[payment.client_id],
          "clientSourceId" => source_by_id[payment.client_id], "clientName" => name_of(clients[payment.client_id]),
          "doctorName" => doctors[payment.doctor_id]
        )
      end
      { "payments" => list, "source" => "PostgreSQL confirmed service payments; historical costs and deposits excluded" }
    end

    def query(resource, key = nil)
      docs = documents(resource)
      rows = identity(include_payload: resource == "clients")
      batch_id = docs.dig("clients", "batchId") || "postgresql"
      case resource
      when "clients"
        appointments = Appointment.all.to_a.group_by(&:client_id)
        payments = Payment.all.to_a.group_by(&:client_id)
        pets = Patient.all.to_a
        pets_by_client = pets.group_by(&:client_id)
        pet_names = pets.to_h { |p| [ p.id, p.name ] }
        doctor_names = Doctor.pluck(:id, :name).to_h
        cards = rows.map do |r|
          original = r.payload.is_a?(String) ? JSON.parse(r.payload) : r.payload
          card = original || {
            "key" => r.client.id, "sourceId" => r.client.id, "name" => "", "petName" => nil, "phone" => nil, "email" => nil,
            "history" => [], "directions" => [], "issues" => [], "visits" => 0, "firstDate" => nil, "lastDate" => nil,
            "historyCostCents" => nil
          }
          receipts = payments.fetch(r.client.id, [])
          card.merge(
            "key" => key_of(r), "canonicalClientId" => r.client.id, "clientId" => r.client.id, "name" => name_of(r.client),
            "phone" => r.client.phone || r.client.phone_raw, "email" => r.client.email,
            "patients" => pets_by_client.fetch(r.client.id, []).map { |p| Json.row(p) },
            "crmAppointments" => appointments.fetch(r.client.id, []).map do |a|
              Json.row(a).merge("doctorName" => doctor_names[a.doctor_id], "patientName" => pet_names[a.patient_id])
            end,
            "crmPaidCents" => receipts.sum(&:amount_cents), "crmPaymentsCount" => receipts.length
          )
        end
        (docs["clients"] || {}).merge(
          "batchId" => batch_id,
          "provenance" => "Historical source projection with canonical PostgreSQL contacts; native finance separate",
          "cards" => cards
        )
      when "analytics"
        per_card = (docs.dig("analytics", "perCard") || {}).dup
        rows.each { |r| per_card[key_of(r)] ||= EMPTY_PER_CARD.deep_dup }
        (docs["analytics"] || {}).merge(
          "perCard" => per_card, "nativeFinance" => finance(rows),
          "provenance" => "Historical analysis at its recorded cutoff; native receipts shown separately, never added to historical cost"
        )
      when "doctors" then docs["doctors"] || { "doctors" => [] }
      when "payments" then finance(rows)
      else
        stored = FullCrmClientWork.pluck(:client_id, :data).to_h
        case resource
        when "client-work"
          row = rows.find { |r| key_of(r) == key } || raise(WorkError.new(404, "Карточка не найдена"))
          snapshot(stored[row.client.id] || Work.empty(source_of(row)), key, batch_id).merge("profile" => profile_of(row))
        when "work-index"
          { "batchId" => batch_id,
            "clients" => rows.select { |r| stored.key?(r.client.id) }.to_h { |r| [ key_of(r), Work.summary(stored[r.client.id]) ] } }
        when "tasks"
          tasks = rows.flat_map do |r|
            record = stored[r.client.id]
            next [] unless record
            record["tasks"].reject { |t| t["archivedAt"] }.map do |t|
              t.merge("clientKey" => key_of(r), "clientOwner" => record["owner"], "revision" => record["revision"])
            end
          end
          { "batchId" => batch_id, "tasks" => tasks }
        when "workflow"
          workflow_snapshot(FullCrmWorkflow.where(id: 1).pick(:data), batch_id, rows)
        else
          raise WorkError.new(404, "Ресурс не найден")
        end
      end
    end

    def workflow_snapshot(value, batch_id, rows)
      data = value || { "revision" => 0, "updatedAt" => nil, "assignments" => [] }
      assignments = data["assignments"].to_h { |a| [ a["sourceId"], a ] }
      { "batchId" => batch_id, "revision" => data["revision"], "updatedAt" => data["updatedAt"],
        "assignments" => rows.select { |r| assignments.key?(source_of(r)) }.to_h { |r| [ key_of(r), assignments[source_of(r)] ] } }
    end

    def fields!(value, names)
      raise WorkError.new(400, "Некорректные поля запроса") unless value.is_a?(Hash) && value.keys.sort == names.sort
    end

    def safe_integer?(value)
      value.is_a?(Integer) && value.abs <= 9_007_199_254_740_991
    end

    def command(resource, body, actor_id)
      raise WorkError.new(405, "Ресурс доступен только для чтения") unless RESOURCES_WRITE.include?(resource)
      ActiveRecord::Base.transaction do
        # A singleton row serializes edits, including first writes, across processes.
        state = FullCrmWorkflow.lock.find_by(id: 1) || raise(WorkError.new(503, "Рабочее хранилище не готово"))
        docs = documents
        batch_id = docs.dig("clients", "batchId") || "postgresql"
        rows = identity
        body = {} unless body.is_a?(Hash)
        raise WorkError.new(409, "Пакет клиентов изменился. Перезагрузи CRM.") if body["batchId"] != batch_id
        row = rows.find { |r| key_of(r) == body["key"] } || raise(WorkError.new(404, "Карточка не найдена"))
        raise WorkError.new(400, "Некорректная версия") unless safe_integer?(body["revision"]) && body["revision"] >= 0

        if resource == "workflow"
          next change_stage(state, body, row, rows, batch_id, actor_id)
        end

        fields!(body, %w[batchId key revision operation operationId payload])
        unless CryptoHelpers.uuid?(body["operationId"]) && body["operation"].is_a?(String) && body["payload"].is_a?(Hash)
          raise WorkError.new(400, "Некорректная операция")
        end
        stored = FullCrmClientWork.find_by(client_id: row.client.id)
        record = stored&.data || Work.empty(source_of(row))
        hash = Json.sha256(JSON.generate([ actor_id, body["operation"], body["payload"].keys.sort.map { |k| [ k, body["payload"][k] ] } ]))
        replay = record["operations"].find { |o| o["id"] == body["operationId"] }
        if replay
          raise WorkError.new(409, "Идентификатор операции уже использован") if replay["hash"] != hash
          next snapshot(record, body["key"], batch_id).merge("profile" => profile_of(row))
        end
        raise WorkError.new(409, "Карточка изменена в другой вкладке. Обнови записи.") if record["revision"] != body["revision"]
        before = record.deep_dup
        profile = nil
        if body["operation"] == "update_profile"
          profile = update_profile(record, body["payload"], row)
        else
          Work.mutate!(record, body)
        end
        record["operations"] << { "id" => body["operationId"], "hash" => hash }
        FullCrmClientWork.upsert({ client_id: row.client.id, data: record }, unique_by: :client_id)
        AuditLog.write!(
          actor: actor_id, entity: "client", entity_id: row.client.id, action: "full_crm.#{body['operation']}",
          before: profile ? { "work" => before, "profile" => profile_of(row) } : before,
          after: profile ? { "work" => record, "profile" => profile } : record
        )
        snapshot(record, body["key"], batch_id).merge("profile" => profile || profile_of(row))
      end
    end

    def update_profile(record, payload, row)
      fields!(payload, %w[name phone email])
      name = payload["name"].is_a?(String) ? payload["name"].strip : nil
      phone = payload["phone"].is_a?(String) ? payload["phone"].strip : nil
      email = payload["email"]
      email_ok = email.nil? || email == "" || (email.is_a?(String) && email.length <= 254 && EMAIL.match?(email))
      unless name&.length&.between?(1, 300) && phone && phone.length <= 120 && email_ok
        raise WorkError.new(400, "Проверь имя, телефон и email")
      end
      row.client.update!(last_name: name, first_name: "", phone: Phone.normalize(phone), phone_raw: phone, email: email.presence)
      record["revision"] += 1
      record["updatedAt"] = Work.now_iso
      record["events"] << { "id" => SecureRandom.uuid, "type" => "profile", "text" => "Изменены контактные данные", "at" => record["updatedAt"] }
      { "name" => name, "phone" => row.client.phone || phone, "email" => row.client.email, "canonicalClientId" => row.client.id }
    end

    def change_stage(state, body, row, rows, batch_id, actor_id)
      fields!(body, %w[batchId key revision stage] + (body.key?("operationId") ? [ "operationId" ] : []))
      if !STAGES.include?(body["stage"]) || (body.key?("operationId") && !CryptoHelpers.uuid?(body["operationId"]))
        raise WorkError.new(400, "Некорректный этап")
      end
      value = state.data
      previous = value["assignments"].find { |a| a["sourceId"] == source_of(row) }&.dig("stage") || "unassigned"
      workflow_hash = Json.sha256(JSON.generate([ actor_id, body["key"], body["stage"] ]))
      if body["operationId"]
        replay = (value["operations"] || []).find { |o| o["id"] == body["operationId"] }
        if replay
          raise WorkError.new(409, "Идентификатор операции уже использован") if replay["hash"] != workflow_hash
          return workflow_snapshot(value, batch_id, rows)
        end
      end
      # A retry of an already applied stage is harmless, but never overwrites a later different stage.
      return workflow_snapshot(value, batch_id, rows) if previous == body["stage"]
      raise WorkError.new(409, "Этапы изменились в другой вкладке. Обнови данные.") if value["revision"] != body["revision"]
      before = value.deep_dup
      at = Work.now_iso
      value["assignments"] = value["assignments"].reject { |a| a["sourceId"] == source_of(row) }
      value["assignments"] << { "sourceId" => source_of(row), "stage" => body["stage"], "updatedAt" => at } if body["stage"] != "unassigned"
      if body["operationId"]
        value["operations"] ||= []
        value["operations"] << { "id" => body["operationId"], "hash" => workflow_hash }
      end
      value["revision"] += 1
      value["updatedAt"] = at
      value["events"] = value["events"] + [ { "sourceId" => source_of(row), "from" => previous, "to" => body["stage"], "at" => at } ]
      state.update_columns(data: value)
      AuditLog.write!(actor: actor_id, entity: "client", entity_id: row.client.id, action: "full_crm.stage_changed", before:, after: value)
      workflow_snapshot(value, batch_id, rows)
    end
  end
end
