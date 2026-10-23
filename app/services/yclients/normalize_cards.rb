module Yclients
  # Brings already imported YCLIENTS cards (`source_key LIKE 'yclients:%'`) to the shape the
  # full workspace reads. History rows gain fields and keep their source values; card-level
  # totals are recomputed. Other legacy cards are never written. Re-running changes nothing.
  module NormalizeCards
    PREFIX = "yclients:"
    LOCK = "vpc-yclients-card-normalize"
    RUN_PREFIX = "yclients-normalize:"

    module_function

    def plan
      rows = LegacyClientRecord.where("source_key LIKE ?", "#{PREFIX}%").pluck(:source_id, :payload)
      changes = []
      invalid = 0
      history_rows = 0
      rows.each do |source_id, payload|
        unless payload.is_a?(Hash) && payload["history"].is_a?(Array)
          invalid += 1
          next
        end
        history_rows += payload["history"].length
        normalized = CardFormat.normalize_card(payload)
        next if Json.canonical(normalized) == Json.canonical(payload)
        changes << { source_id:, payload: normalized, hash: Json.sha256(Json.canonical(normalized)) }
      end
      {
        changes:,
        counts: {
          "version" => CardFormat::VERSION, "yclientsCards" => rows.length, "historyRows" => history_rows,
          "toChange" => changes.length, "alreadyNormalized" => rows.length - changes.length - invalid,
          "skippedWithoutHistory" => invalid
        }
      }
    end

    def dry_run
      Calendar::Service.read_only { plan[:counts] }
    end

    def apply
      ActiveRecord::Base.transaction do
        Leads::Intake.advisory_lock(LOCK)
        result = plan
        updated = result[:changes].sum do |change|
          LegacyClientRecord.where(source_id: change[:source_id]).where("source_key LIKE ?", "#{PREFIX}%")
            .update_all([ "payload = ?::jsonb, hash = ?", Json.dump(change[:payload]), change[:hash] ])
        end
        raise "Normalization plan diverged from destination" if updated != result[:changes].length
        # Read back: a second plan inside the same transaction must find nothing to do.
        raise "Normalization readback mismatch" if plan[:changes].any?
        run_id = "#{RUN_PREFIX}#{Json.iso(Time.current)}:#{SecureRandom.uuid}"
        counts = result[:counts].merge("updated" => updated)
        LegacyImport.raw_insert_all([ { "id" => run_id, "hash" => Json.sha256(CardFormat::VERSION), "manifest" => { "version" => CardFormat::VERSION },
                                       "archive" => { "kind" => "yclients-card-normalize", "updated" => updated }, "counts" => counts } ])
        { "runId" => run_id, "counts" => counts }
      end
    end
  end
end
