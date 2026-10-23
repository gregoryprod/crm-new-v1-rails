module ApplicationHelper
  NBSP = " "

  # "19.10.2026, 21:42" in the CRM time zone (data is stored in UTC).
  def format_date_time(value, zone = crm_time_zone)
    return "" if value.nil?
    time = value.is_a?(String) ? Time.iso8601(value) : value
    time.in_time_zone(zone).strftime("%d.%m.%Y, %H:%M")
  end

  # toLocaleString("ru-RU") with seconds, Moscow time.
  def format_date_time_seconds(value, zone = "Europe/Moscow")
    value.in_time_zone(zone).strftime("%d.%m.%Y, %H:%M:%S")
  end

  def format_phone(e164) = Phone.format(e164)

  # Intl.NumberFormat("ru-RU", { style: "currency", currency: "RUB" }).
  def rub(cents)
    return "Нет данных" unless cents.is_a?(Numeric)
    negative = cents.negative?
    whole, fraction = format("%.2f", cents.abs / 100.0).split(".")
    grouped = whole.reverse.scan(/\d{1,3}/).join(NBSP).reverse
    "#{negative ? '-' : ''}#{grouped},#{fraction}#{NBSP}₽"
  end

  def text_or_dash(value)
    value.nil? || value == "" ? "—" : value.to_s
  end

  def status_label(status) = Lead::STATUS_LABELS.fetch(status, "—")

  SPECIES = [
    [ "собака", /\A(собак|пес|пёс|щен|dog|puppy)/i ],
    [ "кошка", /\A(кошк|кот|котен|котён|cat|kitten)/i ],
    [ "грызун", /\A(грызун|хомя|крыс|мыш|морск|шиншил|дегу|кролик|rodent|hamster|rat|mouse|rabbit)/i ],
    [ "птица", /\A(птиц|попуга|канарей|bird|parrot)/i ]
  ].freeze

  # Reporting dictionary; `patients.species` keeps the submitted text unchanged.
  def species_category(species)
    value = species.strip.downcase
    SPECIES.find { |_, pattern| pattern.match?(value) }&.first || "другое"
  end
end
