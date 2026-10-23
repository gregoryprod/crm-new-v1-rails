require "test_helper"

class AuthTest < ActionDispatch::IntegrationTest
  test "login sets an HttpOnly session cookie; logout revokes it" do
    user = staff
    login_as(user)
    assert_equal({ "user" => { "name" => user.name, "role" => "ADMIN" } }, json)
    cookie = response.headers["Set-Cookie"].to_s
    assert_match(/vpc_session=/, cookie)
    assert_match(/httponly/i, cookie)
    assert_match(/samesite=lax/i, cookie)
    get "/api/auth/session"
    assert_response :ok
    assert_equal user.email, json["user"]["email"]
    assert_nil StaffSession.last.revoked_at

    post "/api/auth/logout", headers: { "Origin" => APP_ORIGIN }
    assert_response :see_other
    assert_equal "#{APP_ORIGIN}/login", response.headers["Location"]
    assert StaffSession.last.revoked_at
    get "/api/auth/session"
    assert_response :unauthorized
  end

  test "same answer for wrong password, unknown and inactive accounts" do
    user = staff
    inactive = staff(active: false)
    [ [ user.email, "wrong-password" ], [ "nobody@example.test", Factory::PASSWORD ], [ inactive.email, Factory::PASSWORD ] ].each do |email, password|
      api(:post, "/api/auth/login", body: { email:, password: })
      assert_response :unauthorized
      assert_equal({ "error" => "invalid_credentials" }, json)
    end
  end

  test "login requires the app origin and is throttled per account" do
    user = staff
    api(:post, "/api/auth/login", body: { email: user.email, password: Factory::PASSWORD }, origin: "https://evil.example")
    assert_response :forbidden
    5.times { api(:post, "/api/auth/login", body: { email: user.email, password: "x" }) }
    api(:post, "/api/auth/login", body: { email: user.email, password: Factory::PASSWORD })
    assert_response :too_many_requests
    assert response.headers["Retry-After"].to_i.positive?
  end

  test "roles: OWNER-only users list, ADMIN-only CRM API" do
    get "/api/crm/leads"
    assert_response :unauthorized
    admin = staff
    login_as(admin)
    get "/api/users"
    assert_response :forbidden
    owner = staff(role: "OWNER")
    login_as(owner)
    get "/api/users"
    assert_response :ok
    assert_not_includes response.body, "password"
  end

  test "deactivation revokes sessions" do
    admin = staff
    login_as(admin)
    Users::Service.set_active("system", admin.id, false)
    get "/api/auth/session"
    assert_response :unauthorized
  end

  test "login page form signs in and pages redirect without a session" do
    get "/crm/leads"
    assert_redirected_to "/login"
    user = staff
    post "/login", params: { email: user.email, password: "wrong" }
    assert_response :unauthorized
    assert_includes response.body, "Неверный email или пароль."
    post "/login", params: { email: user.email, password: Factory::PASSWORD }
    assert_redirected_to "/crm"
    get "/crm"
    assert_redirected_to "/crm/full"
  end

  test "health reports database state only, with the security headers" do
    get "/api/health"
    assert_equal({ "status" => "ok", "database" => "up" }, json)
    assert_equal "DENY", response.headers["X-Frame-Options"]
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_equal "same-origin", response.headers["Referrer-Policy"]
    get "/crm"
    assert_response :see_other
  end
end
