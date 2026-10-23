require "test_helper"

class FullCrmTest < ActionDispatch::IntegrationTest
  setup do
    @admin = staff
    @client, = client_with_patient
    FullCrm::Projections.apply
    login_as(@admin)
    get "/api/crm/full", params: { resource: "clients" }
    @batch = json["batchId"]
    @key = json["cards"].first["key"]
  end

  def work(body) = api(:post, "/api/crm/full?resource=client-work", body: { batchId: @batch, key: @key }.merge(body))

  test "documents agree on one batch (the workspace refuses mismatched sources)" do
    %w[doctors analytics workflow].each do |resource|
      get "/api/crm/full", params: { resource: }
      assert_equal @batch, json["batchId"], resource
    end
    get "/api/crm/full", params: { resource: "analytics" }
    assert json["perCard"].key?(@key)
    get "/api/crm/full-assets"
    assert_equal "SAMEORIGIN", response.headers["X-Frame-Options"]
    assert_includes response.body, "VetPetCare · CRM"
  end

  test "unversioned workspace files are revalidated on every load" do
    get "/full-crm/style.css"
    assert_response :ok
    assert_equal "public, no-cache", response.headers["Cache-Control"]
    assert response.headers["Last-Modified"]
  end

  test "tasks, comments and owner with revisions and idempotent operations" do
    op = SecureRandom.uuid
    work(revision: 0, operation: "create_task", operationId: op, payload: { title: "Позвонить", description: "", dueDay: "2026-10-20", assignee: nil })
    assert_response :ok
    assert_equal 1, json["revision"]
    task_id = json["tasks"].first["id"]
    work(revision: 0, operation: "create_task", operationId: op, payload: { title: "Позвонить", description: "", dueDay: "2026-10-20", assignee: nil })
    assert_equal 1, json["tasks"].length
    work(revision: 0, operation: "set_owner", operationId: SecureRandom.uuid, payload: { owner: "Анна" })
    assert_response :conflict
    work(revision: 1, operation: "set_task_status", operationId: SecureRandom.uuid, payload: { id: task_id, status: "done" })
    assert_equal "done", json["tasks"].first["status"]
    work(revision: 2, operation: "update_profile", operationId: SecureRandom.uuid, payload: { name: "Петров Пётр Иванович", phone: "8 999 000 11 22", email: "" })
    assert_equal "+79990001122", json["profile"]["phone"]
    assert_equal "Петров Пётр Иванович", @client.reload.last_name
    get "/api/crm/full", params: { resource: "tasks" }
    assert_equal [], json["tasks"].reject { |t| t["status"] == "done" }.map { |t| t["title"] } - [ "Позвонить" ]
    assert_equal 3, AuditLog.where(entity: "client", entity_id: @client.id).count
  end

  test "workflow stage changes are serialized and replay-safe" do
    op = SecureRandom.uuid
    api(:post, "/api/crm/full?resource=workflow", body: { batchId: @batch, key: @key, revision: 0, stage: "contact", operationId: op })
    assert_equal 1, json["revision"]
    assert_equal "contact", json["assignments"][@key]["stage"]
    api(:post, "/api/crm/full?resource=workflow", body: { batchId: @batch, key: @key, revision: 0, stage: "contact", operationId: op })
    assert_equal 1, json["revision"]
    api(:post, "/api/crm/full?resource=workflow", body: { batchId: @batch, key: @key, revision: 0, stage: "doctor" })
    assert_response :conflict
    api(:post, "/api/crm/full?resource=workflow", body: { batchId: "other", key: @key, revision: 1, stage: "doctor" })
    assert_equal "Пакет клиентов изменился. Перезагрузи CRM.", json["error"]
  end
end
