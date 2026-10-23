module CalendarHelper
  WEEKDAYS = %w[вс пн вт ср чт пт сб].freeze
  MONTHS = %w[января февраля марта апреля мая июня июля августа сентября октября ноября декабря].freeze
  ATTENDANCE_ACTIONS = {
    "scheduled" => "Снять подтверждение", "confirmed" => "Подтвердить приём", "arrived" => "Клиент пришёл",
    "completed" => "Завершить приём", "no_show" => "Отметить неявку"
  }.freeze
  NEXT_ATTENDANCE = Calendar::Service::TRANSITIONS
  HISTORY_ACTIONS = {
    "appointment.attendance_changed" => "Изменён статус приёма", "appointment.payment_recorded" => "Сохранена оплата услуги",
    "appointment.created" => "Создан приём", "appointment.rescheduled" => "Приём перенесён", "appointment.cancelled" => "Приём отменён"
  }.freeze

  def moscow(value)
    value = Time.iso8601(value) if value.is_a?(String)
    value.getlocal(Calendar::Slots::OFFSET)
  end

  def hm(value) = moscow(value).strftime("%H:%M")

  # "пн, 19 октября"
  def day_label(day)
    date = Date.iso8601(day)
    "#{WEEKDAYS[date.wday]}, #{date.day} #{MONTHS[date.month - 1]}"
  end

  def shift_day(day, offset) = (Date.iso8601(day) + offset).iso8601

  def appointment_status(booking)
    booking["status"] == "cancelled" ? "Отменён" : Appointment::ATTENDANCE_LABELS[booking["attendance"]]
  end

  def history_state(value)
    return "—" unless value.is_a?(Hash)
    [
      value["start"] ? format_date_time_seconds(moscow(value["start"])) : nil,
      value["end"] ? "до #{hm(value['end'])}" : nil,
      value["title"],
      value["status"] == "cancelled" ? "Отменён" : nil,
      value["attendance"] ? Appointment::ATTENDANCE_LABELS[value["attendance"]] : nil,
      value["amountCents"].is_a?(Numeric) ? rub(value["amountCents"]) : nil,
      value["method"] ? Payment::METHOD_LABELS[value["method"]] : nil,
      value["note"].presence,
      value["cancellationReason"].presence
    ].compact.reject { |v| v == "" }.join(" · ")
  end

  # Hidden fields every calendar command carries: idempotency id, revision and where to return.
  def command_fields(operation, revision)
    safe_join([
      hidden_field_tag(:operation, operation, id: nil),
      hidden_field_tag(:operation_id, SecureRandom.uuid, id: nil),
      hidden_field_tag(:expected_revision, revision, id: nil),
      *state.map { |key, value| hidden_field_tag("back[#{key}]", value, id: nil) }
    ])
  end
end
