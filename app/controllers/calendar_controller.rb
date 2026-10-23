# Staff calendar rendered by Rails: every action is a plain form posted to #command, which
# runs the same Calendar::Service as the JSON API and redirects back to the same view.
class CalendarController < ApplicationController
  STATE_KEYS = %w[day view doctor selected q patient service booking_day slots start pay_amount pay_method pay_note pay_review].freeze
  KEEP_SELECTION = %w[set_attendance record_payment].freeze
  MESSAGES = {
    "invalid_attendance_transition" => "Этот переход статуса недоступен. Обнови приём и сверь изменения.",
    "appointment_not_started" => "Завершение и неявку можно отметить после начала приёма.",
    "payment_already_recorded" => "Оплата этого приёма уже сохранена. Обнови календарь.",
    "calendar_conflict" => "Календарь изменился. Проверь изменения на странице и повтори действие.",
    "slot_unavailable" => "Это время уже недоступно. Обнови окна и выбери другое время.",
    "occupied_interval" => "В этом интервале есть приём. Сначала перенеси или отмени его.",
    "invalid_interval" => "Начало интервала должно быть раньше окончания.",
    "invalid_request" => "Проверь заполнение полей.",
    "not_found" => "Запись не найдена. Обнови календарь."
  }.freeze

  helper_method :calendar_url_with, :state

  def show
    require_page_role
    return if performed?
    @data = Calendar::Service.snapshot(day: state["day"], view: state["view"], doctor_id: state["doctor"])
    @selected = state["selected"] && Calendar::Service.booking_by_id(state["selected"])
    @selected = nil if @selected.nil?
    @found = patient_search(state["q"]) if state["q"].to_s.strip.length >= 2
    @patient = state["patient"] && patient_row(state["patient"])
    @service_id = state["service"] || @selected&.dig("serviceId")
    @booking_day = state["booking_day"] || (@selected ? Calendar::Slots.moscow_day(@selected["start"]) : Calendar::Slots.moscow_day(Time.current))
    if state["slots"] == "1" && @service_id && Calendar::Slots.valid_day?(@booking_day)
      @slots = Calendar::Service.slots(day: @booking_day, service_id: @service_id, exclude_id: @selected&.dig("id"))["slots"]
    end
  rescue Calendar::Error => e
    flash.now[:alert] = MESSAGES.fetch(e.code, "Не удалось выполнить действие.")
    @data ||= Calendar::Service.snapshot(day: state["day"], view: state["view"], doctor_id: state["doctor"])
  end

  def command
    require_page_role
    return if performed?
    command = Calendar::Commands.parse(command_from_form)
    back = return_state
    unless command
      return redirect_to(calendar_url_with(back), alert: MESSAGES["invalid_request"], status: :see_other)
    end
    result = Calendar::Service.execute(current_user.id, command)
    back = back.except("selected") unless KEEP_SELECTION.include?(command["operation"])
    back = back.except("slots", "start", "pay_review", "pay_amount", "pay_note", "pay_method", "q", "patient")
    back["selected"] = result["id"] if KEEP_SELECTION.include?(command["operation"])
    redirect_to calendar_url_with(back), notice: "Сохранено.", status: :see_other
  rescue Calendar::Error => e
    redirect_to calendar_url_with(return_state.except("pay_review")), alert: MESSAGES.fetch(e.code, "Не удалось выполнить действие."), status: :see_other
  end

  private

  def failure_event = "calendar.page_failed"

  # Normalized view state from the query string; invalid values fall back to defaults.
  def state
    @state ||= begin
      q = request.query_parameters.slice(*STATE_KEYS).transform_values(&:to_s)
      q["day"] = Calendar::Slots.moscow_day(Time.current) unless Calendar::Slots.valid_day?(q["day"])
      q["view"] = "day" unless %w[day week].include?(q["view"])
      %w[doctor selected patient service].each { |key| q.delete(key) unless CryptoHelpers.uuid?(q[key]) }
      q.delete("booking_day") unless Calendar::Slots.valid_day?(q["booking_day"])
      q.delete_if { |_, v| v.empty? }
      q
    end
  end

  def return_state
    params.permit(back: STATE_KEYS).fetch(:back, {}).to_h.transform_values(&:to_s).reject { |_, v| v.empty? }
  end

  def calendar_url_with(changes = {}, base = state)
    merged = base.merge(changes.transform_keys(&:to_s)).reject { |_, v| v.nil? || v == "" }
    merged.empty? ? "/crm/calendar" : "/crm/calendar?#{URI.encode_www_form(merged.sort)}"
  end

  def patient_search(q)
    q = q.strip[0, 100]
    like = "%#{q.gsub(/[\\%_]/) { |c| "\\#{c}" }}%"
    Patient.joins(:client)
      .where("clients.last_name ILIKE :l OR clients.first_name ILIKE :l OR clients.phone ILIKE :l OR patients.name ILIKE :l", l: like)
      .order("clients.last_name", "patients.id").limit(25)
      .pluck("patients.id", "patients.name", "patients.species", "clients.first_name", "clients.last_name", "clients.phone")
      .map { |values| %w[id name species firstName lastName phone].zip(values).to_h }
  end

  def patient_row(id)
    Patient.joins(:client).where(id:).pick("patients.id", "patients.name", "patients.species", "clients.first_name", "clients.last_name")
      &.then { |values| %w[id name species firstName lastName].zip(values).to_h }
  end

  def int(value)
    Integer(value.to_s, 10, exception: false)
  end

  # Kopecks from a rubles field (JavaScript Math.round(Number(x) * 100) in the old form).
  def cents(value)
    number = Float(value.to_s.tr(",", "."), exception: false)
    number && number.finite? ? (number * 100 + 0.5).floor : nil
  end

  # Form fields → the JSON command shape the service validates.
  def command_from_form
    f = params
    payload = case f[:operation]
    when "add_doctor" then { "name" => f[:name].to_s, "specialty" => f[:specialty].to_s }
    when "upsert_service"
      { "doctorId" => f[:doctor_id].to_s, "title" => f[:title].to_s, "durationMinutes" => int(f[:duration]),
        "priceCents" => f[:price].to_s.strip.empty? ? nil : cents(f[:price]), "prepaymentPercent" => int(f[:prepayment]) }
    when "add_interval"
      { "doctorId" => f[:doctor_id].to_s, "day" => f[:day].to_s, "from" => f[:from].to_s, "to" => f[:to].to_s, "kind" => f[:kind].to_s }
    when "remove_interval" then { "id" => f[:id].to_s }
    when "create_booking"
      { "patientId" => f[:patient_id].to_s, "serviceId" => f[:service_id].to_s, "start" => f[:start].to_s, "note" => f[:note].to_s }
    when "reschedule_booking"
      { "id" => f[:id].to_s, "expectedVersion" => int(f[:expected_version]), "serviceId" => f[:service_id].to_s,
        "start" => f[:start].to_s, "note" => f[:note].to_s }
    when "set_attendance"
      { "id" => f[:id].to_s, "expectedVersion" => int(f[:expected_version]), "attendance" => f[:attendance].to_s }
    when "record_payment"
      { "id" => f[:id].to_s, "expectedVersion" => int(f[:expected_version]), "amountCents" => cents(f[:amount]),
        "method" => f[:method].to_s, "note" => f[:payment_note].to_s }
    when "cancel_booking"
      { "id" => f[:id].to_s, "expectedVersion" => int(f[:expected_version]), "reason" => f[:reason].to_s }
    end
    { "operation" => f[:operation].to_s, "operationId" => f[:operation_id].to_s,
      "expectedRevision" => int(f[:expected_revision]), "payload" => payload }
  end
end
