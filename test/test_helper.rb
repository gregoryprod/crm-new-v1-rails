ENV["RAILS_ENV"] ||= "test"
# Synthetic configuration only; the test database is wiped by the suite.
{
  "APP_ORIGIN" => "http://127.0.0.1:3100",
  "AUTH_SECRET" => "test-synthetic-auth-secret-not-for-production-0001",
  "LEADS_ALLOWED_ORIGINS" => "https://quiz.example.test",
  "CONSENT_PD_VERSION" => "test-pd-v1",
  "CONSENT_MARKETING_VERSION" => "test-marketing-v1",
  "CRM_TIME_ZONE" => "Europe/Moscow",
  "TRUST_PROXY" => "true"
}.each { |key, value| ENV[key] = value }

require_relative "../config/environment"
require "rails/test_help"
require_relative "support/factory"

module ActiveSupport
  class TestCase
    include Factory

    setup do
      AppEnv.reset!
      load Rails.root.join("db/seeds.rb")
    end
  end
end

class ActionDispatch::IntegrationTest
  APP_ORIGIN = "http://127.0.0.1:3100"
  QUIZ_ORIGIN = "https://quiz.example.test"

  setup { host! "127.0.0.1:3100" }

  def json = JSON.parse(response.body)

  def api(method, path, body: nil, origin: APP_ORIGIN, headers: {})
    send(method, path, params: body && JSON.generate(body),
                       headers: { "Content-Type" => "application/json", "Origin" => origin }.compact.merge(headers))
  end

  def login_as(user, password: Factory::PASSWORD)
    api(:post, "/api/auth/login", body: { email: user.email, password: })
    assert_response :ok
  end
end
