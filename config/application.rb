require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "rails/test_unit/railtie"

Bundler.require(*Rails.groups)

require_relative "../lib/env_file"
EnvFile.load(File.expand_path("../.env", __dir__)) unless ENV["RAILS_ENV"] == "production"

module VpcCrm
  class Application < Rails::Application
    config.load_defaults 8.1

    config.autoload_lib(ignore: %w[assets tasks env_file.rb])

    # All timestamps are stored in UTC (timestamptz); pages convert to CRM_TIME_ZONE.
    config.time_zone = "UTC"
    config.active_record.default_timezone = :utc

    # CHECK constraints, composite foreign keys, partial indexes and the exclusion
    # constraint on appointments only survive in SQL form.
    config.active_record.schema_format = :sql

    config.i18n.default_locale = :ru
    config.i18n.available_locales = [ :ru ]

    # Personal data (names, phones, comments) must never reach the logs via parameters.
    config.filter_parameters += [ /.*/ ]

    # Same security headers as the previous app; /api/crm/full-assets relaxes framing to
    # same-origin for the workspace iframe.
    config.action_dispatch.default_headers = {
      "X-Frame-Options" => "DENY",
      "Content-Security-Policy" => "frame-ancestors 'none'; base-uri 'self'; form-action 'self'; object-src 'none'",
      "X-Content-Type-Options" => "nosniff",
      "Referrer-Policy" => "same-origin",
      "Permissions-Policy" => "camera=(), microphone=(), geolocation=()"
    }

    config.generators.system_tests = nil
  end
end
