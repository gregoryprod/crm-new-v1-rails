module Api
  # Readiness: a real SELECT against PostgreSQL; reports only up/down, never configuration.
  class HealthController < ApiController
    def show
      up = begin
        ActiveRecord::Base.connection.select_value("SELECT 1").to_i == 1
      rescue StandardError
        false
      end
      up ? render_json({ "status" => "ok", "database" => "up" }) : render_json({ "status" => "unavailable", "database" => "down" }, 503)
    end
  end
end
