require "test_helper"

class LeadsIntakeTest < ActionDispatch::IntegrationTest
  def submit(body, origin: QUIZ_ORIGIN, ip: "203.0.113.10")
    api(:post, "/api/leads", body:, origin:, headers: { "X-Forwarded-For" => ip })
  end

  test "creates client, patient, lead, consents, audit and outbox in one go" do
    body = lead_body
    submit(body)
    assert_response :created
    assert_equal QUIZ_ORIGIN, response.headers["Access-Control-Allow-Origin"]
    assert_equal "no-store", response.headers["Cache-Control"]
    lead = Lead.find(json["lead_id"])
    assert_equal "NEW", lead.status
    assert_match(/\A[a-f0-9]{64}\z/, json["booking_token"])
    assert_equal "+79991234567", lead.client.phone
    assert_equal "8 (999) 123-45-67", lead.client.phone_raw
    assert_equal %w[MARKETING PD_OFFER], Consent.where(client_id: lead.client_id).pluck(:type).sort
    assert_equal "test-pd-v1", Consent.find_by(client_id: lead.client_id, type: "PD_OFFER").document_version
    assert_equal 1, OutboxEvent.where(type: "lead.created").count
    assert_equal({ "lead_id" => lead.id }, OutboxEvent.last.payload)
    assert_equal "lead.created", AuditLog.find_by(entity_id: lead.id).action
    assert_not lead.raw_payload.key?("idempotency_key")
    assert_equal "https://quiz.example.test/form", lead.page_url
  end

  test "replay with the same key returns the same lead without spending quota" do
    body = lead_body
    submit(body)
    first = json["lead_id"]
    submit(body.merge("phone" => "+7 999 123 45 67", "utm" => nil))
    assert_response :created
    assert_equal "true", response.headers["Idempotent-Replayed"]
    assert_equal first, json["lead_id"]
    assert_equal 1, Lead.count
    submit(body.merge("first_name" => "Ольга"))
    assert_response :conflict
    assert_equal "idempotency_conflict", json["error"]
  end

  test "validation errors list field names only" do
    submit(lead_body("phone" => "abc", "species" => ""))
    assert_response :bad_request
    assert_equal({ "error" => "invalid_request", "fields" => %w[phone species] }, json)
    assert_not_includes response.body, "abc"
  end

  test "honeypot is stored as spam without notification or receipt" do
    submit(lead_body("website" => "http://bot.example"))
    assert_response :created
    assert_nil json["booking_token"]
    assert_equal "SPAM", Lead.find(json["lead_id"]).status
    assert_equal 0, OutboxEvent.count
  end

  test "same phone marks a possible duplicate without merging" do
    submit(lead_body)
    submit(lead_body)
    assert_equal 2, Client.count
    assert Client.order(:created_at).last.possible_duplicate
    assert_equal 1, ClientDuplicateCandidate.count
  end

  test "per-IP and global windows" do
    ENV["LEADS_IP_MAX_PER_WINDOW"] = "2"
    AppEnv.reset!
    2.times { submit(lead_body) }
    submit(lead_body)
    assert_response :too_many_requests
    assert_equal "too_many_requests", json["error"]
    assert response.headers["Retry-After"].to_i.positive?
    submit(lead_body, ip: "203.0.113.99")
    assert_response :created
  ensure
    ENV.delete("LEADS_IP_MAX_PER_WINDOW")
  end

  test "CORS: exact origins only, strict preflight, JSON only, size cap" do
    submit(lead_body, origin: "https://evil.example")
    assert_response :forbidden
    assert_nil response.headers["Access-Control-Allow-Origin"]
    process :options, "/api/leads", headers: { "Origin" => QUIZ_ORIGIN, "Access-Control-Request-Method" => "POST", "Access-Control-Request-Headers" => "content-type" }
    assert_response :no_content
    assert_equal "POST, OPTIONS", response.headers["Access-Control-Allow-Methods"]
    process :options, "/api/leads", headers: { "Origin" => QUIZ_ORIGIN, "Access-Control-Request-Method" => "POST", "Access-Control-Request-Headers" => "x-custom" }
    assert_response :forbidden
    post "/api/leads", params: "a=b", headers: { "Origin" => QUIZ_ORIGIN, "Content-Type" => "application/x-www-form-urlencoded" }
    assert_response :unsupported_media_type
    post "/api/leads", params: "{\"x\":\"#{'a' * 9000}\"}", headers: { "Origin" => QUIZ_ORIGIN, "Content-Type" => "application/json" }
    assert_response :content_too_large
  end

  test "intake is unavailable without configuration" do
    ENV.delete("CONSENT_PD_VERSION")
    AppEnv.reset!
    submit(lead_body)
    assert_response :service_unavailable
    assert_equal "intake_unavailable", json["error"]
  ensure
    ENV["CONSENT_PD_VERSION"] = "test-pd-v1"
  end
end
