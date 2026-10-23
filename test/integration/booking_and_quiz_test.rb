require "test_helper"

class BookingAndQuizTest < ActionDispatch::IntegrationTest
  setup do
    @doctor, @service = doctor_with_service(duration: 60)
    @day = tomorrow
    shift(@doctor, day: @day, from: "10:00", to: "12:00")
  end

  def new_lead
    api(:post, "/api/leads", body: lead_body, origin: QUIZ_ORIGIN)
    [ json["lead_id"], json["booking_token"] ]
  end

  def book(lead_id, token, start: "#{@day}T10:00:00+03:00", operation_id: SecureRandom.uuid, service_id: @service.id)
    api(:post, "/api/booking", body: { operationId: operation_id, leadId: lead_id, bookingToken: token, serviceId: service_id, start: })
  end

  test "public catalog and slots" do
    get "/api/booking/catalog"
    assert_equal [ @doctor.name ], json["doctors"].map { |d| d["name"] }
    assert_equal %w[doctorId durationMinutes id prepaymentPercent priceCents title], json["services"].first.keys.sort
    get "/api/booking/slots", params: { doctorId: @doctor.id, serviceId: @service.id, day: @day }
    assert_equal 5, json["slots"].length
    get "/api/booking/slots", params: { doctorId: SecureRandom.uuid, serviceId: @service.id, day: @day }
    assert_response :bad_request
  end

  test "booking with the receipt: idempotent, one active per lead, wrong token refused" do
    lead_id, token = new_lead
    op = SecureRandom.uuid
    book(lead_id, token, operation_id: op)
    assert_response :ok
    assert_equal({ "accepted" => true }, json.slice("accepted"))
    assert_equal false, json["booking"]["paymentConfirmed"]
    result = json
    book(lead_id, token, operation_id: op)
    assert_equal result, json
    book(lead_id, token, start: "#{@day}T11:00:00+03:00")
    assert_equal "already_booked", json["error"]
    other_id, other_token = new_lead
    book(other_id, other_token)
    assert_equal "slot_unavailable", json["error"]
    book(other_id, token)
    assert_response :forbidden
    assert_equal "invalid_receipt", json["error"]
    assert_equal "appointment.created", AuditLog.where(entity: "appointment").last.action
    assert_not_includes BookingOperation.last.result.to_json, token
  end

  test "built-in quiz: pet, contacts, lead, slot, booking — all through Rails forms" do
    get "/quiz"
    assert_includes response.body, "Кто нуждается в заботе?"
    get "/quiz", params: { step: "contact", species: "Кошка" }
    key = response.body[/name="idempotency_key" value="([^"]+)"/, 1]
    post "/quiz", params: { species: "Кошка", idempotency_key: key, first_name: "Анна", last_name: "Смирнова",
                            phone: "+7 999 765-43-21", consent_pd: "1", website: "" }
    assert_redirected_to "/quiz"
    lead = Lead.last
    assert_equal "Кошка", lead.patient.species
    get "/quiz", params: { doctor: @doctor.id, service: @service.id, day: @day }
    assert_includes response.body, "Записаться на приём"
    operation = response.body[/name="operation_id" value="([^"]+)"/, 1]
    post "/quiz/booking", params: { operation_id: operation, doctor: @doctor.id, service: @service.id, day: @day, start: "#{@day}T07:00:00.000Z" }
    assert_redirected_to "/quiz"
    follow_redirect!
    assert_includes response.body, "Приём записан"
    assert_equal lead.id, Appointment.last.lead_id

    post "/quiz", params: { species: "Кошка", idempotency_key: SecureRandom.uuid, first_name: "1", last_name: "", phone: "x", consent_pd: "1" }
    assert_response :unprocessable_content
    assert_includes response.body, "Проверь имя, фамилию и телефон."
  end
end
