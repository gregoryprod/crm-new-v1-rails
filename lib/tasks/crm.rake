# Operational commands (replacements for the previous npm scripts). Outputs contain
# counts and identifiers only; errors print the class, never values or driver messages.
def crm_task_failure(event, error, detail: false)
  payload = { event:, error: error.class.name.demodulize }
  payload[:detail] = error.message if detail
  warn JSON.generate(payload)
  exit 1
end

def crm_flag(name) = %w[1 true yes].include?(ENV[name].to_s.downcase)

namespace :crm do
  desc "Create the OWNER from OWNER_EMAIL / OWNER_NAME / OWNER_PASSWORD (never overwrites)"
  task seed_owner: :environment do
    AppEnv.server
    input = AppEnv.parse_owner_seed(ENV)
    user = Users::Service.seed_owner(input)
    puts user ? "Создан OWNER #{user.email}." : "Пользователь с этим email уже существует; данные и пароль не изменены."
  rescue AppEnv::Error => e
    warn e.message
    exit 1
  rescue StandardError => e
    crm_task_failure("crm.seed_owner_failed", e)
  end
end

namespace :notifications do
  desc "Deliver outbox notifications to Telegram (ONCE=1 drains due events and exits)"
  task work: :environment do
    exit Notifications::Worker.run(once: crm_flag("ONCE"))
  end
end

namespace :yclients do
  desc "Import YCLIENTS visits, records and shifts: DIRS=dir1,dir2 [APPLY=1] (default dry run)"
  task import_calendar: :environment do
    dirs = ENV.fetch("DIRS", "").split(",").map(&:strip).reject(&:empty?)
    raise Yclients::SourceError, "Supply one or more private YCLIENTS export directories" if dirs.empty?
    source = Yclients::Source.read(dirs.map { |d| File.expand_path(d) })
    result = crm_flag("APPLY") ? Yclients::CalendarImport.apply(source) : { "counts" => Yclients::CalendarImport.dry_run(source) }
    puts JSON.pretty_generate({ "mode" => crm_flag("APPLY") ? "apply" : "dry-run", "hash" => source.digest }.merge(Json.plain(result)))
  rescue StandardError => e
    crm_task_failure("yclients_calendar.import_failed", e, detail: e.is_a?(Yclients::SourceError))
  end

  desc "Normalize imported YCLIENTS cards for the workspace [APPLY=1]"
  task normalize_cards: :environment do
    result = crm_flag("APPLY") ? Yclients::NormalizeCards.apply : { "counts" => Yclients::NormalizeCards.dry_run }
    puts JSON.pretty_generate({ "mode" => crm_flag("APPLY") ? "apply" : "dry-run" }.merge(result))
  rescue StandardError => e
    crm_task_failure("yclients_cards.normalize_failed", e)
  end
end

namespace :full_crm do
  desc "Build workspace documents: [CUTOFF=YYYY-MM-DD] [PREVIEW_NORMALIZED=1 | APPLY=1 [REPLACE=1]]"
  task projections: :environment do
    apply = crm_flag("APPLY")
    raise FullCrm::ProjectionError, "REPLACE=1 requires APPLY=1" if crm_flag("REPLACE") && !apply
    raise FullCrm::ProjectionError, "PREVIEW_NORMALIZED is for dry runs only" if crm_flag("PREVIEW_NORMALIZED") && apply
    cutoff = ENV["CUTOFF"].presence
    result = if apply
      FullCrm::Projections.apply(cutoff:, replace: crm_flag("REPLACE"))
    else
      FullCrm::Projections.dry_run(cutoff:, preview_normalized: crm_flag("PREVIEW_NORMALIZED"))
    end
    puts JSON.pretty_generate({ "mode" => apply ? "apply" : "dry-run" }.merge(result))
  rescue StandardError => e
    crm_task_failure("full_crm.projections_failed", e, detail: e.is_a?(FullCrm::ProjectionError))
  end
end

namespace :legacy do
  desc "Import the previous local JSON workspace into an EMPTY database: SOURCE=dir [ID=local-json-v1] [APPLY=1]"
  task import: :environment do
    root = ENV["SOURCE"].presence or raise ArgumentError, "Supply a verified private source directory; default is dry run"
    bundle = Legacy::Import.read_bundle(File.expand_path(root))
    puts JSON.generate({ "mode" => crm_flag("APPLY") ? "apply" : "dry-run", "hash" => bundle.digest, "counts" => Legacy::Import.counts(bundle) })
    puts JSON.generate(Legacy::Import.apply(bundle, ENV.fetch("ID", "local-json-v1"))) if crm_flag("APPLY")
  rescue StandardError => e
    crm_task_failure("legacy.import_failed", e)
  end
end

namespace :full_crm do
  desc "Import ready workspace documents (clients/doctors/analytics.json) once: SOURCE=dir [APPLY=1]"
  task import_documents: :environment do
    source = ENV["SOURCE"].presence or raise ArgumentError, "SOURCE=private directory required"
    docs = FullCrm::Projections::KEYS.to_h { |key| [ key, JSON.parse(File.read(File.join(File.expand_path(source), "#{key}.json"))) ] }
    batch = docs["clients"]["batchId"]
    unless docs["clients"]["cards"].is_a?(Array) && batch && docs["doctors"]["batchId"] == batch &&
           docs["analytics"]["batchId"] == batch && docs["analytics"]["perCard"].is_a?(Hash)
      raise ArgumentError, "Inconsistent projection bundle"
    end
    %w[workflow.json client-work.json].each do |name|
      raise ArgumentError, "Auxiliary work exists: review and import explicitly before cutover" if File.exist?(File.join(source, name))
    end
    ActiveRecord::Base.transaction do
      Leads::Intake.advisory_lock("full-crm-import-v1")
      mapped = LegacyClientRecord.pluck(:source_id, :source_key).to_h
      ids = Set.new
      docs["clients"]["cards"].each do |card|
        id = card["sourceId"].to_s
        raise ArgumentError, "Projection identity mismatch" if id.empty? || ids.include?(id) || !docs["analytics"]["perCard"].key?(card["key"])
        raise ArgumentError, "Legacy mapping differs; do not infer identity" if mapped[id] != card["key"]
        ids << id
      end
      existing = FullCrmDocument.where(key: docs.keys).pluck(:key, :data).to_h
      docs.each do |key, value|
        raise ArgumentError, "Existing projection differs; explicit migration required" if existing.key?(key) && Json.canonical(existing[key]) != Json.canonical(value)
        FullCrmDocument.create!(key:, data: value) if crm_flag("APPLY") && !existing.key?(key)
      end
      raise ActiveRecord::Rollback unless crm_flag("APPLY")
    end
    puts JSON.generate({ "mode" => crm_flag("APPLY") ? "applied" : "dry-run", "cards" => docs["clients"]["cards"].length })
  rescue StandardError => e
    crm_task_failure("full_crm.import_documents_failed", e, detail: e.is_a?(ArgumentError))
  end
end
