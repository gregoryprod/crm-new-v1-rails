require "test_helper"

class CalendarTest < ActionDispatch::IntegrationTest
  setup do
    @admin = staff
    login_as(@admin)
    @doctor, @service = doctor_with_service(duration: 30)
    @day = tomorrow
    shift(@doctor, day: @day)
    _client, @patient = client_with_patient
  end

  def command(operation, payload, revision: CalendarState.find(1).revision, operation_id: SecureRandom.uuid)
    api(:post, "/api/crm/calendar", body: { operation:, operationId: operation_id, expectedRevision: revision, payload: })
  end

  def slot(time) = "#{@day}T#{time}:00+03:00"

  test "booking, double booking, idempotent replay and revision conflict" do
    get "/api/crm/calendar/slots", params: { day: @day, serviceId: @service.id }
    assert_equal "#{@day}T06:00:00.000Z", json["slots"].first["start"]
    assert_equal 35, json["slots"].length

    op = SecureRandom.uuid
    command("create_booking", { patientId: @patient.id, serviceId: @service.id, start: slot("10:00"), note: "" }, operation_id: op)
    assert_response :ok
    assert_equal true, json["saved"]
    first = json
    command("create_booking", { patientId: @patient.id, serviceId: @service.id, start: slot("10:00"), note: "" }, operation_id: op, revision: 0)
    assert_equal first, json
    command("create_booking", { patientId: @patient.id, serviceId: @service.id, start: slot("10:15"), note: "" })
    assert_response :conflict
    assert_equal "slot_unavailable", json["error"]
    command("create_booking", { patientId: @patient.id, serviceId: @service.id, start: slot("11:00"), note: "" }, revision: 0)
    assert_equal "calendar_conflict", json["error"]

    get "/api/crm/calendar", params: { day: @day }
    assert_equal 1, json["bookings"].length
    assert_equal "Шарик", json["bookings"].first["patientName"]
    assert_equal "appointment.created", json["history"].first["action"]
  end

  test "database exclusion constraint forbids overlaps even outside the service" do
    base = { doctor_id: @doctor.id, service_id: @service.id, client_id: @patient.client_id, patient_id: @patient.id,
             title: "x", prepayment_percent: 0 }
    Appointment.create!(base.merge(start_at: Time.iso8601(slot("12:00")), end_at: Time.iso8601(slot("12:30"))))
    error = assert_raises(ActiveRecord::StatementInvalid) do
      Appointment.create!(base.merge(start_at: Time.iso8601(slot("12:15")), end_at: Time.iso8601(slot("12:45"))))
    end
    assert_equal "23P01", LogEvent.sqlstate(error)
  end

  test "attendance transitions and one payment per completed appointment" do
    past = Appointment.create!(doctor_id: @doctor.id, service_id: @service.id, client_id: @patient.client_id, patient_id: @patient.id,
                               title: "Консультация", prepayment_percent: 0, price_cents: 150_000,
                               start_at: 2.hours.ago, end_at: 90.minutes.ago)
    command("set_attendance", { id: past.id, expectedVersion: 1, attendance: "completed" })
    assert_equal "invalid_attendance_transition", json["error"]
    command("set_attendance", { id: past.id, expectedVersion: 1, attendance: "arrived" })
    command("set_attendance", { id: past.id, expectedVersion: 2, attendance: "completed" })
    assert_response :ok
    command("record_payment", { id: past.id, expectedVersion: 3, amountCents: 150_000, method: "card", note: "" })
    assert_response :ok
    command("record_payment", { id: past.id, expectedVersion: 4, amountCents: 1, method: "cash", note: "" })
    assert_equal "payment_already_recorded", json["error"]
    assert_equal 150_000, Payment.sum(:amount_cents)
    get "/crm/analytics"
    assert_includes response.body, "1 500,00 ₽"
  end

  test "Rails calendar page runs commands from plain forms" do
    get "/crm/calendar", params: { day: @day }
    assert_response :ok
    assert_includes response.body, @doctor.name
    revision = CalendarState.find(1).revision
    form = { operation_id: SecureRandom.uuid, expected_revision: revision, back: { day: @day, view: "day" } }
    post "/crm/calendar", params: form.merge(operation: "create_booking", patient_id: @patient.id, service_id: @service.id, start: slot("14:00"), note: "из формы")
    assert_response :see_other
    assert_equal "Сохранено.", flash[:notice]
    appointment = Appointment.find_by(note: "из формы")
    assert appointment

    post "/crm/calendar", params: form.merge(operation_id: SecureRandom.uuid, expected_revision: revision, operation: "cancel_booking", id: appointment.id, expected_version: 1, reason: "x")
    assert_equal "Календарь изменился. Проверь изменения на странице и повтори действие.", flash[:alert]

    get "/crm/calendar", params: { day: @day, selected: appointment.id, service: @service.id, booking_day: @day, slots: "1" }
    assert_includes response.body, "Перенести приём"
    assert_includes response.body, "Отменить приём"

    post "/crm/calendar", params: form.merge(operation_id: SecureRandom.uuid, expected_revision: CalendarState.find(1).revision,
                                             operation: "add_interval", doctor_id: @doctor.id, day: @day, from: "19:00", to: "18:00", kind: "break")
    assert_equal "Начало интервала должно быть раньше окончания.", flash[:alert]
  end
end
