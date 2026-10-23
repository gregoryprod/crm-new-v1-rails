# Base of the JSON API. Contract kept from the previous Node app: `Cache-Control: no-store`,
# error bodies `{ "error": code }`, bodies read with a hard byte cap, CSRF defence by an
# exact Origin match, and failures logged as event + class + SQLSTATE only.
class ApiController < ActionController::API
  include ActionController::Cookies

  class Halt < StandardError; end
  TooLarge = Object.new.freeze

  # No query cache: claims, row locks (FOR UPDATE), INSERT/UPDATE … RETURNING and
  # clock_timestamp() reads must hit PostgreSQL every time, never a cached result.
  around_action { |_, action| ActiveRecord::Base.uncached(&action) }

  rescue_from StandardError do |error|
    raise error if error.is_a?(Halt)
    LogEvent.error(failure_event, error)
    render_error(500, internal_error_code) unless performed?
  end

  private

  def failure_event = "#{controller_name}.request_failed"
  def internal_error_code = "internal_error"

  def render_json(body, status = 200, headers = {})
    response.headers["Cache-Control"] = "no-store"
    headers.each { |name, value| response.headers[name] = value }
    render body: Json.dump(body), status:, content_type: "application/json"
  end

  def render_error(status, code, headers = {})
    render_json({ "error" => code }, status, headers)
  end

  def json_content?(exact: false)
    type = request.headers["Content-Type"].to_s.downcase
    exact ? type.split(";").first.to_s.strip == "application/json" : type.start_with?("application/json")
  end

  # Returns the parsed value, nil for malformed JSON / invalid UTF-8, or TooLarge.
  def read_json_body(max_bytes)
    declared = request.headers["Content-Length"]
    return TooLarge if declared&.match?(/\A\d+\z/) && declared.to_i > max_bytes
    raw = request.body.read(max_bytes + 1).to_s
    return TooLarge if raw.bytesize > max_bytes
    text = raw.force_encoding(Encoding::UTF_8)
    return nil unless text.valid_encoding?
    JSON.parse(text)
  rescue JSON::ParserError, EncodingError
    nil
  end

  def same_origin?
    origin = request.headers["Origin"]
    !origin.nil? && origin == AppEnv.server.app_origin
  end

  # Client IP only from a trusted reverse proxy; otherwise unknown (no per-IP limit).
  def client_ip
    return nil unless AppEnv.server.trust_proxy
    forwarded = request.headers["X-Forwarded-For"].to_s.split(",").first.to_s.strip
    forwarded.presence || request.headers["X-Real-IP"].to_s.strip.presence
  end

  def query_params
    request.query_parameters
  end

  # 401 without a valid session, 403 without the role; a database failure during the
  # lookup becomes a generic 500 (logged by class only).
  def require_staff(role = "ADMIN")
    session = begin
      Auth::Service.session_user(cookies[SessionCookie.cookie_name])
    rescue StandardError => e
      LogEvent.error("crm.auth_failed", e)
      render_error(500, "internal_error")
      raise Halt
    end
    unless session
      render_error(401, "unauthenticated")
      raise Halt
    end
    unless session.user.has_role?(role)
      render_error(403, "forbidden")
      raise Halt
    end
    session
  end

  def require_same_origin!
    return if same_origin?
    render_error(403, "forbidden_origin")
    raise Halt
  end

  def process_action(*)
    super
  rescue Halt
    nil
  end
end
