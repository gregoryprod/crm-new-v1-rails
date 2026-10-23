module Clients
  # Client directory and cards for staff. Matching phones never merge clients
  # automatically; a person decides.
  module Directory
    PAGE = 25
    MAX_DUPLICATE_CANDIDATES = 20

    module_function

    # Returns { "q" => ..., "page" => ... } or nil for an invalid query (strict, like zod).
    def parse_query(params)
      return nil unless (params.keys - %w[q page]).empty?
      q = params["q"].nil? ? "" : params["q"]
      return nil unless q.is_a?(String)
      q = q.strip
      return nil if q.length > 100
      raw = params["page"]
      page = if raw.nil? then 1
      elsif raw.is_a?(String) && raw.strip.match?(/\A-?\d+(\.0+)?\z/) then raw.to_i
      end
      return nil if page.nil? || !page.between?(1, 10_000)
      { "q" => q, "page" => page }
    end

    def list(query)
      scope = Client.all
      if query["q"].present?
        pattern = TextRules.case_insensitive_regex(query["q"])
        scope = scope.where("clients.last_name ~ :p OR clients.first_name ~ :p OR clients.phone_raw ~ :p", p: pattern)
      end
      rows = scope.left_joins(:legacy_client_record).order(created_at: :desc, id: :asc).limit(PAGE).offset((query["page"] - 1) * PAGE)
        .pluck("clients.id", :last_name, :first_name, :phone, :phone_raw, "legacy_client_records.source_key")
        .map { |values| %w[id lastName firstName phone phoneRaw sourceKey].zip(values).to_h }
      total = scope.count
      { "rows" => rows, "total" => total, "page" => query["page"], "pages" => [ 1, (total.to_f / PAGE).ceil ].max }
    end

    def details(id)
      return nil unless CryptoHelpers.uuid?(id)
      client = Client.find_by(id:)
      return nil unless client
      legacy = LegacyClientRecord.where(client_id: id).pick(:source_id, :source_key, :payload)
      {
        "client" => Json.row(client),
        "legacy" => legacy && { "sourceId" => legacy[0], "sourceKey" => legacy[1], "payload" => legacy[2] },
        "patients" => Patient.where(client_id: id).pluck(:id, :name, :species).map { |values| %w[id name species].zip(values).to_h }
      }
    end

    # Returns [:saved, id] | [:not_found] | [:conflict]; idempotent by operationId.
    def create_confirmed_patient(actor, client_id, input)
      ActiveRecord::Base.transaction do
        next [ :not_found ] unless Client.lock("FOR SHARE").where(id: client_id).exists?
        inserted = ActiveRecord::Base.connection.select_value(ApplicationRecord.sql(<<~SQL, input["operationId"], client_id, input["name"], input["species"]))
          INSERT INTO patients (id, client_id, name, species) VALUES (?, ?, ?, ?) ON CONFLICT DO NOTHING RETURNING id
        SQL
        unless inserted
          old = Patient.find_by(id: input["operationId"], client_id:)
          next [ :conflict ] if old.nil? || old.name != input["name"] || old.species != input["species"]
          next [ :saved, old.id ]
        end
        AuditLog.write!(actor:, entity: "patient", entity_id: inserted, action: "patient.created",
                        after: { client_id:, name: input["name"], species: input["species"], identity_confirmed_by_staff: true })
        [ :saved, inserted ]
      end
    end

    def parse_patient(body)
      return nil unless body.is_a?(Hash) && (body.keys - %w[operationId name species confirmed]).empty?
      return nil unless CryptoHelpers.uuid?(body["operationId"]) && body["confirmed"] == true
      name = body["name"].is_a?(String) ? body["name"].strip : nil
      species = body["species"].is_a?(String) ? body["species"].strip : nil
      return nil unless name&.length&.between?(1, 200) && species&.length&.between?(1, 50)
      { "operationId" => body["operationId"], "name" => name, "species" => species }
    end

    # Links in both directions: older cards this one points at and newer cards pointing here.
    def duplicate_candidates(client_id)
      links = ClientDuplicateCandidate.where("client_id = :id OR candidate_client_id = :id", id: client_id)
        .limit(MAX_DUPLICATE_CANDIDATES * 5).pluck(:client_id, :candidate_client_id)
      ids = links.map { |a, b| a == client_id ? b : a }.uniq
      return [] if ids.empty?
      newest_lead = Arel.sql("(SELECT l.id FROM leads l WHERE l.client_id = clients.id ORDER BY l.created_at DESC, l.id DESC LIMIT 1)")
      Client.where(id: ids).order(created_at: :desc, id: :desc)
        .pluck(:id, :last_name, :first_name, :phone, :created_at, newest_lead)
        .map { |values| %w[clientId lastName firstName phone createdAt leadId].zip(values).to_h }
    end
  end
end
