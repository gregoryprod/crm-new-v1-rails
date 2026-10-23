module Leads
  # Staff side of leads: filtered list, card and audited updates.
  module Staff
    PAGE_SIZE = 25
    MAX_PAGE = 1_000
    MAX_QUERY = 100
    MAX_COMMENT = 2_000

    Query = Struct.new(:status, :from, :to, :source, :q, :page, keyword_init: true)

    module_function

    def iso_date(value)
      return nil unless value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      date = Date.strptime(value, "%Y-%m-%d")
      date.iso8601 == value && date.year.between?(2000, 2100) ? value : nil
    rescue Date::Error
      nil
    end

    def query_text(value, min: 1)
      return nil if value.length > MAX_QUERY * 4
      cleaned = value.unicode_normalize(:nfc).gsub(TextRules::CONTROL, "").gsub(/[[:space:]﻿]+/, " ").strip
      cleaned.length.between?(min, MAX_QUERY) ? cleaned : nil
    end

    # Lenient parsing of URL filters: invalid or oversized values are dropped (and reported
    # by name) instead of failing the page. Only the first value of a repeated parameter counts.
    def parse_query(params)
      query = Query.new(page: 1)
      invalid = []
      parsers = {
        "status" => ->(v) { Lead::STATUSES.include?(v) ? v : nil },
        "from" => ->(v) { iso_date(v) },
        "to" => ->(v) { iso_date(v) },
        "source" => ->(v) { query_text(v) },
        "q" => ->(v) { query_text(v, min: 2) },
        "page" => ->(v) { v.match?(/\A\s*\d+\s*\z/) && v.to_i.between?(1, MAX_PAGE) ? v.to_i : nil }
      }
      parsers.each do |name, parser|
        raw = params[name]
        value = raw.is_a?(Array) ? raw.first : raw
        next if value.nil? || value == ""
        parsed = value.is_a?(String) ? parser.(value) : nil
        parsed.nil? ? invalid << name : query[name] = parsed
      end
      if query.from && query.to && query.from > query.to
        invalid << "to"
        query.to = nil
      end
      [ query, invalid ]
    end

    # Phone-like queries search the E.164 digits ("8…" is the RU trunk prefix); others names.
    def search_terms(q)
      return {} if q.nil?
      if q.match?(/\A[\d\s()+.-]+\z/) && q.match?(/\d/)
        digits = q.gsub(/\D/, "")
        digits = "7#{digits[1..]}" if digits.length == 11 && digits.start_with?("8")
        return { phone_digits: digits }
      end
      { text: q }
    end

    def filtered_scope(query)
      zone = AppEnv.server.crm_time_zone
      scope = Lead.joins(:client)
      scope = scope.where(status: query.status) if query.status
      scope = scope.where("leads.created_at >= (?::date)::timestamp AT TIME ZONE ?", query.from, zone) if query.from
      scope = scope.where("leads.created_at < ((?::date + 1)::timestamp) AT TIME ZONE ?", query.to, zone) if query.to
      scope = scope.where("(leads.utm ->> 'source') ~ ?", "^#{TextRules.case_insensitive_regex(query.source)}$") if query.source
      terms = search_terms(query.q)
      if terms[:phone_digits]
        scope = scope.where("strpos(clients.phone, ?) > 0", terms[:phone_digits])
      elsif terms[:text]
        pattern = TextRules.case_insensitive_regex(terms[:text])
        scope = scope.where(
          "clients.last_name ~ :p OR clients.first_name ~ :p OR (clients.last_name || ' ' || clients.first_name) ~ :p " \
          "OR (clients.first_name || ' ' || clients.last_name) ~ :p", p: pattern
        )
      end
      scope
    end

    def list_page(query)
      scope = filtered_scope(query)
      rows = scope.joins(:patient).joins("LEFT JOIN users ON users.id = leads.assigned_to")
        .order(created_at: :desc, id: :desc).limit(PAGE_SIZE).offset((query.page - 1) * PAGE_SIZE)
        .pluck("leads.id", "leads.created_at", "leads.status", "clients.last_name", "clients.first_name",
               "clients.phone", "patients.species", "clients.possible_duplicate", Arel.sql("leads.utm ->> 'source'"), "users.name")
        .map { |values| %w[id createdAt status lastName firstName phone species possibleDuplicate utmSource assignedName].zip(values).to_h }
      total = scope.count
      { "rows" => rows, "total" => total, "page" => query.page, "pageSize" => PAGE_SIZE,
        "pages" => [ 1, (total.to_f / PAGE_SIZE).ceil ].max }
    end

    def card(id)
      return nil unless CryptoHelpers.uuid?(id)
      lead = Lead.includes(:client, :patient).find_by(id:)
      return nil unless lead
      client = lead.client
      history = AuditLog.where(entity: "lead", entity_id: id).order(at: :desc, id: :desc).limit(100)
        .map { |e| { "id" => e.id, "actor" => e.actor, "action" => e.action, "before" => e.before, "after" => e.after, "at" => e.at } }
      referenced = Set.new
      referenced << lead.assigned_to if lead.assigned_to
      history.each do |entry|
        referenced << entry["actor"] unless entry["actor"] == "system"
        [ entry["before"], entry["after"] ].each do |side|
          referenced << side["assigned_to"] if side.is_a?(Hash) && side["assigned_to"].is_a?(String)
        end
      end
      names = User.where(id: referenced.select { |v| CryptoHelpers.uuid?(v) }).pluck(:id, :name).to_h
      {
        "id" => lead.id, "version" => lead.version, "createdAt" => lead.created_at, "updatedAt" => lead.updated_at,
        "status" => lead.status, "assignedTo" => lead.assigned_to, "comment" => lead.comment,
        "quizVersion" => lead.quiz_version, "utm" => lead.utm, "pageUrl" => lead.page_url,
        "honeypot" => lead.raw_payload.is_a?(Hash) && lead.raw_payload["honeypot"] == true,
        "client" => {
          "id" => client.id, "lastName" => client.last_name, "firstName" => client.first_name, "phone" => client.phone,
          "phoneRaw" => client.phone_raw, "source" => client.source, "possibleDuplicate" => client.possible_duplicate
        },
        "patient" => { "id" => lead.patient.id, "species" => lead.patient.species },
        "candidates" => Clients::Directory.duplicate_candidates(client.id),
        "consents" => Consent.where(client_id: client.id).order(:granted_at, :type)
          .map { |c| { "type" => c.type, "granted" => c.granted, "documentVersion" => c.document_version, "grantedAt" => c.granted_at } },
        "history" => history,
        "staff" => User.where(active: true).order(:name, :id).map { |u| { "id" => u.id, "name" => u.name, "role" => u.role } },
        "bookings" => Appointment.joins(:doctor).where(lead_id: id).order(:start_at)
          .pluck("appointments.id", :title, :start_at, :end_at, "appointments.status", "doctors.name")
          .map { |values| %w[id title start end status doctor].zip(values).to_h },
        "delivery" => Outbox.lead_delivery(id),
        "userNames" => names
      }
    end

    UPDATE_FIELDS = %w[expectedVersion status assigned_to comment body].freeze

    # Returns [data, nil] or [nil, invalid_fields].
    def parse_update(body)
      return [ nil, [ "body" ] ] unless body.is_a?(Hash)
      fields = []
      (body.keys - %w[expectedVersion status assigned_to comment]).each { fields << "body" }
      version = body["expectedVersion"]
      fields << "expectedVersion" unless version.is_a?(Integer) && version >= 1
      data = { expected_version: version }
      if body.key?("status")
        Lead::STATUSES.include?(body["status"]) ? data[:status] = body["status"] : fields << "status"
      end
      if body.key?("assigned_to")
        value = body["assigned_to"]
        value.nil? || CryptoHelpers.uuid?(value) ? data[:assigned_to] = value : fields << "assigned_to"
      end
      if body.key?("comment")
        value = body["comment"]
        if value.nil?
          data[:comment] = nil
        elsif value.is_a?(String) && value.length <= MAX_COMMENT * 2 && (cleaned = value.gsub("\r\n", "\n").strip).length <= MAX_COMMENT
          data[:comment] = cleaned
        else
          fields << "comment"
        end
      end
      fields << "body" unless data.key?(:status) || data.key?(:assigned_to) || data.key?(:comment)
      fields.any? ? [ nil, fields.uniq.sort ] : [ data, nil ]
    end

    # Applies only fields that actually change, under a row lock, in one transaction with an
    # audit record of those fields. A no-op writes nothing. A new assignee must be an active
    # staff member; an unchanged inactive assignee may stay.
    def update(actor_id, id, input)
      return { kind: "not_found" } unless CryptoHelpers.uuid?(id)
      ActiveRecord::Base.transaction do
        current = Lead.lock.find_by(id:)
        next({ kind: "not_found" }) unless current
        next({ kind: "stale", version: current.version }) if input[:expected_version] != current.version

        state = ->(lead) { { version: lead.version, status: lead.status, assigned_to: lead.assigned_to, comment: lead.comment } }
        before_state = state.(current)
        next_status = input.key?(:status) ? input[:status] : current.status
        next_assigned = input.key?(:assigned_to) ? input[:assigned_to] : current.assigned_to
        next_comment = input.key?(:comment) ? input[:comment].presence : current.comment
        changes = {}
        before = {}
        after = {}
        if next_status != current.status
          changes[:status] = next_status
          before["status"] = current.status
          after["status"] = next_status
        end
        if next_assigned != current.assigned_to
          if next_assigned && !User.lock("FOR SHARE").where(id: next_assigned, active: true).exists?
            next({ kind: "invalid", fields: [ "assigned_to" ] })
          end
          changes[:assigned_to] = next_assigned
          before["assigned_to"] = current.assigned_to
          after["assigned_to"] = next_assigned
        end
        if next_comment != current.comment
          changes[:comment] = next_comment
          before["comment"] = current.comment
          after["comment"] = next_comment
        end
        next({ kind: "unchanged", state: before_state }) if changes.empty?

        current.update!(changes.merge(version: current.version + 1))
        AuditLog.write!(actor: actor_id, entity: "lead", entity_id: id, action: "lead.updated", before:, after:)
        { kind: "updated", state: state.(current) }
      end
    end
  end
end
