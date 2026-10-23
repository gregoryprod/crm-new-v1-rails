module Leads
  # Public quiz intake.
  #
  # 1. A known idempotency key is answered from the database without writes and without
  #    spending rate-limit quota (same data → same lead_id, different data → conflict).
  # 2. Otherwise one transaction: advisory lock on the key and a re-check, then quota
  #    admission under the global window row lock, then the phone lock and the writes
  #    client → duplicate links → patient → lead → consents → audit → outbox. Any failure,
  #    including at COMMIT, rolls everything back, quota counters included.
  # Honeypot hits are stored as SPAM (no data loss) without an outbox event.
  module Intake
    Result = Data.define(:kind, :lead_id, :spam, :possible_duplicate, :scope, :retry_after_seconds) do
      def self.of(kind, **fields)
        new(kind:, lead_id: nil, spam: false, possible_duplicate: false, scope: nil, retry_after_seconds: nil, **fields)
      end
    end

    MAX_USER_AGENT = 256
    MAX_DUPLICATE_CANDIDATES = 20

    module_function

    def submit(lead, ip:, user_agent:)
      env = AppEnv.server
      leads_env = AppEnv.leads

      known = find_by_key(lead.idempotency_key)
      return resolve_existing(known, lead) if known

      ip = Throttle.valid_ip(ip)
      ip_hash = ip ? CryptoHelpers.keyed_hash(env.auth_secret, "lead-ip", ip) : nil
      user_agent = user_agent&.slice(0, MAX_USER_AGENT)

      begin
        ActiveRecord::Base.transaction do
          advisory_lock("lead-key:#{lead.idempotency_key}")
          raced = find_by_key(lead.idempotency_key)
          next resolve_existing(raced, lead) if raced

          quota = Throttle.admit(ip, secret: env.auth_secret, ip_max: leads_env.ip_max_per_window,
                                     global_max: leads_env.global_max_per_window, window_minutes: leads_env.window_minutes)
          next Result.of("rate_limited", scope: quota.scope, retry_after_seconds: quota.retry_after_seconds) if quota.limited

          advisory_lock("lead-phone:#{lead.phone}")
          candidates = Client.where(phone: lead.phone).order(created_at: :desc, id: :desc)
            .limit(MAX_DUPLICATE_CANDIDATES).pluck(:id)
          possible_duplicate = candidates.any?
          client = Client.create!(last_name: lead.last_name, first_name: lead.first_name, phone: lead.phone,
                                  phone_raw: lead.phone_raw, source: "QUIZ", possible_duplicate:)
          candidates.each do |candidate_id|
            ActiveRecord::Base.connection.exec_insert(
              "INSERT INTO client_duplicate_candidates (client_id, candidate_client_id) VALUES ($1, $2) ON CONFLICT DO NOTHING",
              "Duplicate Candidate", [ client.id, candidate_id ]
            )
          end
          patient = Patient.create!(client_id: client.id, species: lead.species)

          status = lead.honeypot ? "SPAM" : "NEW"
          record = Lead.create!(
            client_id: client.id, patient_id: patient.id, status:, quiz_version: lead.quiz_version,
            raw_payload: Payload.raw_payload(lead), utm: lead.utm, page_url: lead.page_url,
            ip_hash:, user_agent:, idempotency_key: lead.idempotency_key
          )

          consents = [
            { type: "PD_OFFER", granted: true, document_version: leads_env.consent_pd_version },
            { type: "MARKETING", granted: lead.consent_marketing, document_version: leads_env.consent_marketing_version }
          ]
          # The server chooses the document version and the time (now()), never the client.
          consents.each do |item|
            ActiveRecord::Base.connection.exec_insert(<<~SQL, "Consent Insert", [ client.id, item[:type], item[:granted], item[:document_version], ip_hash ])
              INSERT INTO consents (client_id, type, granted, document_version, granted_at, source, ip_hash)
              VALUES ($1, $2, $3, $4, now(), 'QUIZ', $5)
            SQL
          end

          AuditLog.write!(
            actor: "system", entity: "lead", entity_id: record.id, action: "lead.created",
            after: {
              status:, client_id: client.id, patient_id: patient.id, possible_duplicate:,
              duplicate_candidates: candidates.length, spam_reason: lead.honeypot ? "honeypot" : nil,
              consents: consents.map { |item| { type: item[:type], granted: item[:granted], document_version: item[:document_version] } }
            }
          )
          OutboxEvent.create!(type: "lead.created", payload: { "lead_id" => record.id }) if status == "NEW"

          Result.of("created", lead_id: record.id, spam: status == "SPAM", possible_duplicate:)
        end
      rescue ActiveRecord::RecordNotUnique
        # Defensive: the advisory lock makes this unreachable for the same key, but the unique
        # index stays the final arbiter.
        existing = find_by_key(lead.idempotency_key)
        raise unless existing
        resolve_existing(existing, lead)
      end
    end

    def find_by_key(key)
      Lead.where(idempotency_key: key).pick(:id, :raw_payload)
    end

    def resolve_existing((id, raw_payload), lead)
      Payload.same_submission?(raw_payload, lead) ? Result.of("replayed", lead_id: id) : Result.of("conflict", lead_id: id)
    end

    def advisory_lock(name)
      ActiveRecord::Base.connection.execute(ApplicationRecord.sql("SELECT pg_advisory_xact_lock(hashtextextended(?, 0))", name))
    end
  end
end
