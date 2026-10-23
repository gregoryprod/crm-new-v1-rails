module Legacy
  # One-off import of the previous local JSON workspace (clients, catalog, quiz leads and
  # schedule) into an empty database. Insert-only, one transaction, one immutable source
  # hash; a re-run with the same migration id is a replay, a changed source is refused.
  module Import
    NAMES = %w[clients.json booking-catalog.json intake-leads.json scheduling.json lead-processing.json workflow.json
               client-work.json analytics.json doctors.json manifest.json].freeze
    AUXILIARY = %w[lead-processing.json workflow.json client-work.json].freeze
    Bundle = Data.define(:archive, :manifest, :source, :catalog, :submissions, :schedule, :digest)

    module_function

    def check(condition, message = "Invalid source")
      raise ArgumentError, message unless condition
    end

    def read_bundle(root)
      archive = {}
      manifest = {}
      NAMES.each do |name|
        path = File.join(root, name)
        next unless File.exist?(path)
        data = File.binread(path)
        archive[name] = JSON.parse(data.force_encoding(Encoding::UTF_8))
        manifest[name] = { "sha256" => Digest::SHA256.hexdigest(data), "bytes" => data.bytesize }
      end
      # Auxiliary workflow stores require an explicit operational mapping; archiving alone
      # must never silently discard live work during a cutover.
      AUXILIARY.each { |name| raise ArgumentError, "Source contains auxiliary work requiring a reviewed mapping" if archive.key?(name) }

      source = archive["clients.json"]
      check(source.is_a?(Hash) && source["batchId"].is_a?(String) && source["cards"].is_a?(Array))
      source["cards"].each do |c|
        check(c.is_a?(Hash) && c["key"].is_a?(String) && !c["key"].empty? && c["name"].is_a?(String) && c["phone"].is_a?(String) &&
              c["history"].is_a?(Array) && c["history"].all?(Hash) &&
              ((c["sourceId"].is_a?(String) && !c["sourceId"].empty?) || c["sourceId"].is_a?(Integer)))
      end
      catalog = archive["booking-catalog.json"]
      check(catalog.is_a?(Hash) && catalog["doctors"].is_a?(Array) && catalog["services"].is_a?(Array))
      catalog["doctors"].each do |d|
        check(d.is_a?(Hash) && d["id"].is_a?(String) && !d["id"].empty? && d["name"].is_a?(String) && !d["name"].empty?)
        d["specialty"] = "" unless d.key?("specialty")
        check(d["specialty"].is_a?(String))
      end
      catalog["services"].each { |s| check_service(s) }
      submissions = (archive["intake-leads.json"] || { "leads" => [] })["leads"]
      check(submissions.is_a?(Array))
      submissions.each do |l|
        check(l.is_a?(Hash) && CryptoHelpers.uuid?(l["id"]) && %w[first_name last_name phone quiz_version idempotency_key].all? { |k| l[k].is_a?(String) } &&
              l["species"].is_a?(String) && !l["species"].empty? && l["consent_pd"] == true && [ true, false ].include?(l["consent_marketing"]) &&
              valid_iso?(l["createdAt"]) && (!l.key?("bookingToken") || l["bookingToken"].to_s.match?(/\A[a-f0-9]{64}\z/)))
      end
      schedule = archive["scheduling.json"] || { "revision" => 0, "services" => catalog["services"], "intervals" => [], "bookings" => [] }
      check(schedule.is_a?(Hash) && schedule["revision"].is_a?(Integer) && schedule["revision"] >= 0 &&
            schedule["services"].is_a?(Array) && schedule["intervals"].is_a?(Array) && schedule["bookings"].is_a?(Array))
      schedule["vacations"] ||= []
      schedule["templates"] ||= []
      schedule["services"].each { |s| check_service(s) }
      schedule["intervals"].each do |i|
        check(i.is_a?(Hash) && CryptoHelpers.uuid?(i["id"]) && i["doctorId"].is_a?(String) && %w[shift break].include?(i["kind"]) &&
              i["start"].is_a?(Numeric) && i["end"].is_a?(Numeric))
      end
      schedule["bookings"].each do |b|
        check(b.is_a?(Hash) && CryptoHelpers.uuid?(b["id"]) && (b["leadId"].nil? || CryptoHelpers.uuid?(b["leadId"])) &&
              b["doctorId"].is_a?(String) && b["serviceId"].is_a?(String) && b["title"].is_a?(String) &&
              (b["priceCents"].nil? || (b["priceCents"].is_a?(Integer) && b["priceCents"].between?(0, 2_147_483_647))) &&
              b["prepaymentPercent"].is_a?(Integer) && b["prepaymentPercent"].between?(0, 100) &&
              b["start"].is_a?(Numeric) && b["end"].is_a?(Numeric) && %w[active cancelled].include?(b["status"]) && valid_iso?(b["createdAt"]))
      end

      unique = ->(rows) { rows.map { |r| r["id"] }.uniq.length == rows.length }
      cards = source["cards"]
      if cards.map { |c| c["sourceId"].to_s }.uniq.length != cards.length || cards.map { |c| c["key"] }.uniq.length != cards.length ||
         !unique.(catalog["doctors"]) || !unique.(schedule["services"]) || !unique.(schedule["intervals"]) ||
         !unique.(schedule["bookings"]) || !unique.(submissions)
        raise ArgumentError, "Ambiguous source identities"
      end
      doctor_ids = catalog["doctors"].map { |d| d["id"] }.to_set
      service_ids = schedule["services"].map { |s| s["id"] }.to_set
      lead_ids = submissions.map { |l| l["id"] }.to_set
      schedule["services"].each { |s| raise ArgumentError, "Unknown source doctor" unless doctor_ids.include?(s["doctorId"]) }
      schedule["intervals"].each { |i| raise ArgumentError, "Invalid source interval" if !doctor_ids.include?(i["doctorId"]) || i["start"] >= i["end"] }
      schedule["bookings"].each do |b|
        if !doctor_ids.include?(b["doctorId"]) || !service_ids.include?(b["serviceId"]) || b["start"] >= b["end"] || (b["leadId"] && !lead_ids.include?(b["leadId"]))
          raise ArgumentError, "Invalid source booking"
        end
      end
      Bundle.new(archive:, manifest:, source:, catalog:, submissions:, schedule:, digest: Digest::SHA256.hexdigest(JSON.generate(manifest)))
    end

    def check_service(s)
      check(s.is_a?(Hash) && s["id"].is_a?(String) && !s["id"].empty? && s["doctorId"].is_a?(String) && !s["doctorId"].empty? &&
            s["title"].is_a?(String) && !s["title"].empty? && s["durationMinutes"].is_a?(Integer) && s["durationMinutes"].between?(5, 480) &&
            (s["priceCents"].nil? || (s["priceCents"].is_a?(Integer) && s["priceCents"].between?(0, 2_147_483_647))) &&
            s["prepaymentPercent"].is_a?(Integer) && s["prepaymentPercent"].between?(0, 100))
    end

    def valid_iso?(value)
      value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?Z\z/)
    end

    def counts(bundle)
      {
        "clients" => bundle.source["cards"].length, "historyRows" => bundle.source["cards"].sum { |c| c["history"].length },
        "leads" => bundle.submissions.length, "doctors" => bundle.catalog["doctors"].length,
        "services" => bundle.schedule["services"].length, "intervals" => bundle.schedule["intervals"].length,
        "bookings" => bundle.schedule["bookings"].length, "vacations" => bundle.schedule["vacations"].length,
        "templates" => bundle.schedule["templates"].length
      }
    end

    def ms(value) = Time.at(value / 1000.0).utc
    def id(kind, value) = CryptoHelpers.legacy_id(kind, value)

    def apply(bundle, migration_id, patient_map = {})
      ActiveRecord::Base.transaction do
        Leads::Intake.advisory_lock("vpc-legacy-import")
        previous = LegacyImport.find_by(id: migration_id)
        if previous
          raise "Source changed since import" if LegacyImport.content_hash_of(id: migration_id) != bundle.digest
          next({ "replayed" => true, "counts" => previous.counts })
        end
        # Import into a dedicated empty destination only, never combine with synthetic QA.
        existing = ActiveRecord::Base.connection.select_value(
          "SELECT (SELECT count(*) FROM clients)+(SELECT count(*) FROM appointments)+(SELECT count(*) FROM doctors)+(SELECT count(*) FROM leads)"
        ).to_i
        raise "Destination must be empty" unless existing.zero?

        bundle.source["cards"].each_slice(200) do |part|
          rows = part.map { |c| Rows.client_rows(c) }
          Client.insert_all!(rows.map { |r| r[:client] })
          LegacyClientRecord.raw_insert_all(rows.map { |r| r[:record] })
        end
        bundle.catalog["doctors"].each { |d| Doctor.create!(id: id("doctor", d["id"]), name: d["name"], specialty: d["specialty"]) }
        bundle.schedule["services"].each do |s|
          DoctorService.create!(id: id("service", s["id"]), doctor_id: id("doctor", s["doctorId"]), title: s["title"],
                                duration_minutes: s["durationMinutes"], price_cents: s["priceCents"], prepayment_percent: s["prepaymentPercent"])
        end
        lead_patients = {}
        bundle.submissions.each do |l|
          phone = Phone.normalize(l["phone"]) || raise("Source lead phone requires review")
          client_id = id("lead-client", l["id"])
          patient_id = id("lead-patient", l["id"])
          created = Time.iso8601(l["createdAt"])
          lead_patients[l["id"]] = { client_id:, patient_id: }
          Client.create!(id: client_id, last_name: l["last_name"], first_name: l["first_name"], phone:, phone_raw: l["phone"],
                         source: "QUIZ", created_at: created)
          Patient.create!(id: patient_id, client_id:, species: l["species"], created_at: created)
          raw = { "last_name" => l["last_name"], "first_name" => l["first_name"], "phone" => phone, "species" => l["species"],
                  "consent_pd" => true, "consent_marketing" => l["consent_marketing"], "quiz_version" => l["quiz_version"], "honeypot" => false }
          Lead.create!(id: l["id"], client_id:, patient_id:, status: "NEW", quiz_version: l["quiz_version"],
                       idempotency_key: l["idempotency_key"], raw_payload: raw, created_at: created, updated_at: created)
          [ [ "PD_OFFER", true ], [ "MARKETING", l["consent_marketing"] ] ].each do |type, granted|
            Consent.create!(client_id:, type:, granted:, document_version: "legacy-local-unknown", granted_at: created, source: "QUIZ")
          end
          BookingReceipt.create!(lead_id: l["id"], token_hash: Booking::Receipt.token_hash(Booking::Receipt.token_for(l["id"])),
                                 legacy_token_hash: l["bookingToken"] ? Booking::Receipt.token_hash(l["bookingToken"]) : nil,
                                 expires_at: Booking::Receipt.expiry)
          AuditLog.create!(actor: "system", entity: "lead", entity_id: l["id"], action: "lead.imported", at: created,
                           after: { "source" => "local-json", "source_id" => l["id"] })
        end
        bundle.schedule["intervals"].each do |i|
          CalendarInterval.create!(id: i["id"], doctor_id: id("doctor", i["doctorId"]), kind: i["kind"], start_at: ms(i["start"]), end_at: ms(i["end"]))
        end
        doctor_ids = bundle.catalog["doctors"].map { |d| d["id"] }.to_set
        bundle.schedule["vacations"].each do |v|
          raise ArgumentError, "Invalid source vacation" unless v["doctorId"].is_a?(String) && v["fromDay"].is_a?(String) && v["toDay"].is_a?(String) && CryptoHelpers.uuid?(v["id"])
          start = Time.iso8601("#{v['fromDay']}T00:00:00+03:00").utc rescue nil
          finish = (Time.iso8601("#{v['toDay']}T00:00:00+03:00").utc + 86_400 rescue nil)
          raise ArgumentError, "Invalid source vacation" if !doctor_ids.include?(v["doctorId"]) || start.nil? || finish.nil? || start >= finish
          CalendarInterval.create!(id: v["id"], doctor_id: id("doctor", v["doctorId"]), kind: "break", start_at: start, end_at: finish)
        end
        bundle.schedule["bookings"].each do |b|
          relation = b["leadId"] && lead_patients[b["leadId"]]
          unless relation
            patient_id = patient_map[b["id"]] || raise("Manual source booking requires an explicit confirmed patient mapping")
            p = Patient.find_by(id: patient_id)
            raise "Patient mapping does not belong to source client" if p.nil? || p.client_id != id("client", b["clientSourceId"].to_s)
            relation = { client_id: p.client_id, patient_id: p.id }
          end
          Appointment.create!(id: b["id"], lead_id: b["leadId"], **relation, doctor_id: id("doctor", b["doctorId"]),
                              service_id: id("service", b["serviceId"]), title: b["title"], price_cents: b["priceCents"],
                              prepayment_percent: b["prepaymentPercent"], start_at: ms(b["start"]), end_at: ms(b["end"]),
                              status: b["status"], note: b["note"] || "", created_at: Time.iso8601(b["createdAt"]))
          (b["events"] || []).each_with_index do |e, index|
            AuditLog.create!(id: id("event", "#{b['id']}:#{index}"), actor: "system", entity: "appointment", entity_id: b["id"],
                             action: "appointment.imported", at: e["at"].is_a?(String) ? Time.iso8601(e["at"]) : Time.iso8601(b["createdAt"]),
                             before: e["from"], after: e.merge("source" => "local-json"))
          end
        end
        ActiveRecord::Base.connection.execute(ApplicationRecord.sql(
          "INSERT INTO calendar_state (id, revision) VALUES (1, ?) ON CONFLICT (id) DO UPDATE SET revision = EXCLUDED.revision",
          bundle.schedule["revision"]
        ))
        totals = counts(bundle)
        LegacyImport.raw_insert_all([ { "id" => migration_id, "hash" => bundle.digest, "manifest" => bundle.manifest, "archive" => bundle.archive, "counts" => totals } ])
        # Read back each immutable payload (jsonb reorders keys: compare canonical JSON).
        wanted = bundle.source["cards"].to_h { |c| [ c["sourceId"].to_s, Json.canonical(c) ] }
        stored = LegacyClientRecord.pluck(:source_id, :payload)
        if stored.length != totals["clients"] || stored.any? { |source_id, payload| Json.canonical(payload) != wanted[source_id] }
          raise "Import readback mismatch"
        end
        { "replayed" => false, "counts" => totals }
      end
    end
  end
end
