require "test_helper"

class StaffLeadsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = staff
    api(:post, "/api/leads", body: lead_body("utm" => { "source" => "VK" }), origin: QUIZ_ORIGIN)
    @lead = Lead.find(json["lead_id"])
    api(:post, "/api/leads", body: lead_body("last_name" => "Ёлкина", "phone" => "+7 912 000-11-22", "utm" => nil), origin: QUIZ_ORIGIN)
    login_as(@admin)
  end

  test "list filters by status, source, phone and Cyrillic name" do
    get "/api/crm/leads"
    assert_equal 2, json["total"]
    get "/api/crm/leads", params: { source: "vk" }
    assert_equal [ @lead.id ], json["rows"].map { |r| r["id"] }
    get "/api/crm/leads", params: { q: "89991234567" }
    assert_equal 1, json["total"]
    get "/api/crm/leads", params: { q: "елкин" }
    assert_equal [ "Ёлкина" ], json["rows"].map { |r| r["lastName"] }
    get "/api/crm/leads", params: { status: "BAD", page: "0", from: "2026-02-30" }
    assert_equal %w[status from page].sort, json["invalid"].sort
  end

  test "card and audited optimistic update" do
    get "/api/crm/leads/#{@lead.id}"
    card = json["lead"]
    assert_equal 1, card["version"]
    assert_equal "Доставлено в Telegram" == card["delivery"], false
    api(:patch, "/api/crm/leads/#{@lead.id}", body: { expectedVersion: 1, status: "IN_PROGRESS", assigned_to: @admin.id, comment: " Позвонить\r\n " })
    assert_response :ok
    assert_equal({ "result" => "updated", "lead" => { "version" => 2, "status" => "IN_PROGRESS", "assigned_to" => @admin.id, "comment" => "Позвонить" } }, json)
    audit = AuditLog.where(entity_id: @lead.id, action: "lead.updated").last
    assert_equal({ "status" => "NEW", "assigned_to" => nil, "comment" => nil }, audit.before)

    api(:patch, "/api/crm/leads/#{@lead.id}", body: { expectedVersion: 1, status: "DONE" })
    assert_response :conflict
    assert_equal({ "error" => "stale_version", "version" => 2 }, json)
    api(:patch, "/api/crm/leads/#{@lead.id}", body: { expectedVersion: 2, status: "IN_PROGRESS" })
    assert_equal "unchanged", json["result"]
    api(:patch, "/api/crm/leads/#{@lead.id}", body: { expectedVersion: 2, assigned_to: staff(active: false).id })
    assert_equal({ "error" => "invalid_request", "fields" => [ "assigned_to" ] }, json)
    api(:patch, "/api/crm/leads/#{@lead.id}", body: { expectedVersion: 2, foo: 1 })
    assert_equal [ "body" ], json["fields"]
    api(:patch, "/api/crm/leads/#{@lead.id}", body: { expectedVersion: 2, status: "DONE" }, origin: "https://evil.example")
    assert_response :forbidden
  end

  test "pages render the list and card; the form update keeps the draft on conflict" do
    get "/crm/leads"
    assert_response :ok
    assert_includes response.body, "Иванова Мария"
    get "/crm/leads/#{@lead.id}"
    assert_includes response.body, "Ожидает отправки"
    assert_includes response.body, "utm_source"

    patch "/crm/leads/#{@lead.id}", params: { expected_version: 1, status: "DONE", assigned_to: "", comment: "Готово" }
    assert_redirected_to "/crm/leads/#{@lead.id}"
    patch "/crm/leads/#{@lead.id}", params: { expected_version: 1, status: "SPAM", assigned_to: "", comment: "Черновик" }
    assert_response :unprocessable_content
    assert_includes response.body, "Конфликт версии"
    assert_includes response.body, "Черновик"
    assert_equal "DONE", @lead.reload.status
    get "/crm/leads/00000000-0000-4000-8000-000000000000"
    assert_response :not_found
  end

  test "clients directory, card and confirmed patient" do
    get "/api/crm/clients", params: { q: "иванова" }
    assert_equal 1, json["total"]
    client_id = json["rows"].first["id"]
    operation = SecureRandom.uuid
    api(:post, "/api/crm/clients/#{client_id}/patients", body: { operationId: operation, name: "Мурка", species: "кошка", confirmed: true })
    assert_response :ok
    api(:post, "/api/crm/clients/#{client_id}/patients", body: { operationId: operation, name: "Мурка", species: "кошка", confirmed: true })
    assert_response :ok
    api(:post, "/api/crm/clients/#{client_id}/patients", body: { operationId: operation, name: "Другая", species: "кошка", confirmed: true })
    assert_response :conflict
    post "/crm/clients/#{client_id}/patients", params: { operation_id: SecureRandom.uuid, name: "Барсик", species: "кот", confirmed: "1" }
    assert_redirected_to "/crm/clients/#{client_id}"
    get "/crm/clients/#{client_id}"
    assert_includes response.body, "Барсик"
    assert_equal 3, Patient.where(client_id:).count
  end
end
