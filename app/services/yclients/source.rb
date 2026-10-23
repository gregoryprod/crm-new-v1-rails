module Yclients
  # Reader for YCLIENTS period exports (`raw/*.json` of yclients-export-period.ps1). Only
  # the fields needed by the calendar import are kept; everything else is dropped at parse
  # time so the importer never carries unrelated personal data around.
  module Source
    PET_NAME_FIELD = "klichka-pitomtsa"
    PET_BREED_FIELD = "poroda-i-pol-pitomtsa"
    ATTENDANCE = { "-1" => "Клиент не пришёл", "0" => "Ожидание", "1" => "Клиент пришёл", "2" => "Клиент подтвердил" }.freeze

    Record = Struct.new(:id, :staff_id, :staff_name, :services, :client, :client_without_card, :date, :datetime,
                        :create_date, :last_change_date, :seance_length, :length, :attendance, :deleted, :comment,
                        :paid_full, keyword_init: true)
    Data_ = Struct.new(:records, :profiles, :schedule, :manifest, :digest, :stats, keyword_init: true)
    Slot = Data.define(:staff_id, :date, :from, :to)

    class Invalid < StandardError; end

    module_function

    def int(value) = value.is_a?(Integer) ? value : (raise Invalid)
    def text(value) = value.nil? ? "" : (value.is_a?(String) ? value.strip : (raise Invalid))
    def number(value) = value.nil? ? nil : (value.is_a?(Numeric) && value.to_f.finite? ? value : (raise Invalid))
    def object(value) = value.is_a?(Hash) ? value : (raise Invalid)

    def profile(item)
      object(item)
      visits = item["visits"]
      raise Invalid unless visits.nil? || visits.is_a?(Integer)
      {
        "id" => int(item["id"]), "name" => text(item["name"]), "surname" => text(item["surname"]),
        "patronymic" => text(item["patronymic"]), "display_name" => text(item["display_name"]),
        "phone" => text(item["phone"]), "email" => text(item["email"]), "spent" => number(item["spent"]),
        "paid" => number(item["paid"]), "balance" => number(item["balance"]), "visits" => visits,
        "custom_fields" => item["custom_fields"]
      }
    end

    def brief(item)
      object(item)
      { "id" => int(item["id"]), "name" => text(item["name"]), "display_name" => text(item["display_name"]),
        "phone" => text(item["phone"]), "email" => text(item["email"]), "custom_fields" => item["custom_fields"] }
    end

    # YCLIENTS sends null/[]/{} for a record without a client (a service block), but an
    # object with a name and no `id` for a visitor without a client card.
    def client_of(value)
      return [ nil, false ] unless value.is_a?(Hash)
      [ brief(value), false ]
    rescue Invalid
      named = %w[name surname patronymic display_name phone email].any? { |key| value[key].is_a?(String) && value[key].strip != "" }
      [ nil, named ]
    end

    def record(item)
      object(item)
      staff = item["staff"]
      raise Invalid unless staff.nil? || staff.is_a?(Hash)
      services = item["services"]
      services = [] if services.nil?
      raise Invalid unless services.is_a?(Array)
      deleted = item["deleted"]
      raise Invalid unless deleted.nil? || deleted == true || deleted == false
      client, without_card = client_of(item["client"])
      Record.new(
        id: int(item["id"]), staff_id: int(item["staff_id"]), staff_name: staff ? text(staff["name"]) : nil,
        services: services.map { |s| object(s); { "id" => int(s["id"]), "title" => text(s["title"]), "cost" => number(s["cost"]) } },
        client:, client_without_card: without_card,
        date: text(item["date"]), datetime: text(item["datetime"]), create_date: text(item["create_date"]),
        last_change_date: text(item["last_change_date"]), seance_length: number(item["seance_length"]),
        length: number(item["length"]), attendance: int(item["attendance"]), deleted: deleted || false,
        comment: text(item["comment"]), paid_full: number(item["paid_full"])
      )
    end

    def schedule_day(item)
      object(item)
      raise Invalid unless item["date"].is_a?(String) && item["slots"].is_a?(Array)
      slots = item["slots"].map do |s|
        object(s)
        raise Invalid unless s["from"].is_a?(String) && s["to"].is_a?(String)
        { "from" => s["from"], "to" => s["to"] }
      end
      { "staff_id" => int(item["staff_id"]), "date" => item["date"], "slots" => slots }
    end

    def parse_item(kind, item, name, index)
      send(kind, item)
    rescue Invalid
      raise SourceError, "Invalid item in #{name} of export #{index + 1}"
    end

    # Accepts an export root (with `raw/`) or the `raw` directory itself.
    def raw_directory(dir)
      nested = File.join(dir, "raw")
      File.exist?(File.join(nested, "records.json")) ? nested : dir
    end

    def read(dirs)
      raise SourceError, "No YCLIENTS export directory" if dirs.empty?
      manifest = {}
      records = {}
      profiles = {}
      days = {}
      dirs.each_with_index do |dir, index|
        raw = raw_directory(dir)
        load = lambda do |name, required|
          file = File.join(raw, name)
          unless File.exist?(file)
            raise SourceError, "Missing #{name} in export #{index + 1}" if required
            next []
          end
          data = File.binread(file)
          manifest["#{index + 1}/#{name}"] = { "sha256" => Digest::SHA256.hexdigest(data), "bytes" => data.bytesize }
          parsed = begin
            JSON.parse(data.force_encoding(Encoding::UTF_8).delete_prefix("﻿"))
          rescue JSON::ParserError, EncodingError
            # Parser messages may quote source text; never propagate them.
            raise SourceError, "Invalid JSON in #{name} of export #{index + 1}"
          end
          raise SourceError, "#{name} of export #{index + 1} must be an array" unless parsed.is_a?(Array)
          parsed
        end
        load.("records.json", true).each do |item|
          r = parse_item(:record, item.is_a?(Hash) ? item : {}, "records.json", index)
          previous = records[r.id]
          # Overlapping exports: the most recently changed copy wins; on a tie the later directory.
          records[r.id] = r if previous.nil? || r.last_change_date >= previous.last_change_date
        end
        load.("clients.json", false).each do |item|
          p = parse_item(:profile, item, "clients.json", index)
          profiles[p["id"]] = p
        end
        # A later export replaces the whole working day of a doctor.
        load.("staff_schedule.json", true).each do |item|
          d = parse_item(:schedule_day, item, "staff_schedule.json", index)
          days["#{d['staff_id']}|#{d['date']}"] = d
        end
      end
      schedule = days.values.flat_map { |d| d["slots"].map { |s| Slot.new(staff_id: d["staff_id"], date: d["date"], from: s["from"], to: s["to"]) } }
        .sort_by { |s| [ s.staff_id, s.date, s.from ] }
      list = records.values.sort_by(&:id)
      Data_.new(
        records: list, profiles:, schedule:, manifest:, digest: Digest::SHA256.hexdigest(JSON.generate(manifest)),
        stats: {
          "directories" => dirs.length, "records" => list.length, "recordsDeleted" => list.count(&:deleted),
          "recordsWithoutClient" => list.count { |r| r.client.nil? && !r.client_without_card },
          "recordsClientWithoutCard" => list.count(&:client_without_card),
          "clientProfiles" => profiles.size, "scheduleDays" => days.size, "scheduleSlots" => schedule.length
        }
      )
    end

    def custom_field(holder, code)
      fields = holder.is_a?(Hash) ? holder["custom_fields"] : nil
      return nil unless fields.is_a?(Hash)
      value = fields[code]
      value.is_a?(String) && value.strip != "" ? value.strip : nil
    end

    def cents(rub)
      rub.is_a?(Numeric) && rub.to_f.finite? ? (rub.to_f * 100 + 0.5).floor : nil # JavaScript Math.round
    end

    def record_cost_cents(r)
      r.services.empty? ? nil : cents(r.services.sum { |s| s["cost"] || 0 })
    end

    def record_title(r)
      r.services.map { |s| s["title"] }.reject(&:empty?).join(", ")
    end

    # The card the legacy YCLIENTS converter produced, normalized for the full workspace.
    def card(client_id, client_records, full)
      recs = client_records.sort_by(&:datetime)
      short = recs.find(&:client)&.client
      name = full&.dig("display_name").presence ||
        [ full&.dig("surname"), full&.dig("name"), full&.dig("patronymic") ].select(&:present?).join(" ").presence ||
        short&.dig("display_name").presence || short&.dig("name").presence || ""
      pet_name = custom_field(full, PET_NAME_FIELD)
      history = recs.map do |r|
        {
          "id" => r.id.to_s, "sourceDateTime" => r.datetime.presence || r.date, "doctor" => r.staff_name || "",
          "doctorSourceId" => r.staff_id.to_s, "service" => record_title(r), "petName" => pet_name,
          "costCents" => cents(r.services.sum { |s| s["cost"] || 0 }),
          "attendance" => ATTENDANCE.fetch(r.attendance.to_s, r.attendance.to_s), "deleted" => r.deleted,
          "paidFull" => r.paid_full == 1
        }
      end
      live = history.reject { |h| h["deleted"] }
      CardFormat.normalize_card(
        "key" => "yclients:#{client_id}", "sourceId" => client_id.to_s, "name" => name,
        "phone" => full&.dig("phone").presence || short&.dig("phone").presence || "",
        "email" => full&.dig("email").presence || short&.dig("email").presence,
        "petName" => pet_name, "breedInfo" => custom_field(full, PET_BREED_FIELD),
        "sourceReportedPaidCents" => cents(full&.dig("paid")), "sourceReportedSpentCents" => cents(full&.dig("spent")),
        "sourceReportedBalanceCents" => cents(full&.dig("balance")),
        "sourceVisitsTotal" => full&.dig("visits").is_a?(Integer) ? full["visits"] : nil,
        "history" => history, "directions" => live.map { |h| h["doctor"] }.reject(&:empty?).uniq, "issues" => []
      )
    end
  end
end
