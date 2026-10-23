module Api
  # Public quiz intake: no staff session. Responses never contain submitted values, only
  # `lead_id`, an error code and (for 400) the names of invalid fields.
  class LeadsController < ApiController
    MAX_BODY_BYTES = 8 * 1024
    ALLOWED_HEADERS = %w[content-type].freeze

    # CORS preflight: exact allow-listed origin, POST, at most the Content-Type header.
    def preflight
      config = leads_config or return render_error(503, "intake_unavailable")
      origin = allowed_origin(config)
      unless origin && allowed_preflight?
        response.headers["Cache-Control"] = "no-store"
        response.headers["Vary"] = "Origin"
        return head :forbidden
      end
      response.headers.merge!(
        "Cache-Control" => "no-store", "Access-Control-Allow-Origin" => origin,
        "Access-Control-Allow-Methods" => "POST, OPTIONS", "Access-Control-Allow-Headers" => "Content-Type",
        "Access-Control-Max-Age" => "600", "Vary" => "Origin, Access-Control-Request-Method, Access-Control-Request-Headers"
      )
      head :no_content
    end

    def create
      config = leads_config or return render_error(503, "intake_unavailable")
      origin = allowed_origin(config)
      cors = origin ? { "Access-Control-Allow-Origin" => origin, "Access-Control-Expose-Headers" => "Retry-After", "Vary" => "Origin" } : { "Vary" => "Origin" }
      @cors = cors
      return render_error(403, "forbidden_origin", cors) unless origin
      return render_error(415, "unsupported_media_type", cors) unless json_content?
      body = read_json_body(MAX_BODY_BYTES)
      return render_error(413, "payload_too_large", cors) if body.equal?(TooLarge)
      parsed = Leads::Payload.parse(body)
      return render_json({ "error" => "invalid_request", "fields" => parsed.fields }, 400, cors) unless parsed.ok

      result = Leads::Intake.submit(parsed.lead, ip: client_ip, user_agent: request.headers["User-Agent"])
      case result.kind
      when "created"
        LogEvent.info("lead.created", lead_id: result.lead_id, spam: result.spam, possible_duplicate: result.possible_duplicate)
        render_json({ "lead_id" => result.lead_id, "status" => "created", "booking_token" => Booking::Receipt.issue(result.lead_id) }, 201, cors)
      when "replayed"
        LogEvent.info("lead.replayed", lead_id: result.lead_id)
        render_json({ "lead_id" => result.lead_id, "status" => "created", "booking_token" => Booking::Receipt.issue(result.lead_id) },
                    201, cors.merge("Idempotent-Replayed" => "true"))
      when "conflict"
        LogEvent.warn("lead.idempotency_conflict", lead_id: result.lead_id)
        render_error(409, "idempotency_conflict", cors)
      when "rate_limited"
        LogEvent.warn("lead.rate_limited", scope: result.scope)
        render_error(429, "too_many_requests", cors.merge("Retry-After" => result.retry_after_seconds.to_s))
      end
    end

    private

    def failure_event = "lead.intake_failed"

    def render_error(status, code, headers = @cors || {})
      super
    end

    def leads_config
      AppEnv.leads
    rescue AppEnv::Error => e
      # Variable names and rules only; values are never part of AppEnv::Error.
      LogEvent.error("lead.config_invalid", e, issues: e.issues.join("; "))
      nil
    end

    def allowed_origin(config)
      origin = request.headers["Origin"]
      return nil if origin.nil? || origin == "null"
      config.allowed_origins.include?(origin) ? origin : nil
    end

    def allowed_preflight?
      return false unless request.headers["Access-Control-Request-Method"] == "POST"
      requested = request.headers["Access-Control-Request-Headers"]
      return true if requested.nil? || requested.empty?
      requested.split(",").map { |h| h.strip.downcase }.reject(&:empty?).all? { |h| ALLOWED_HEADERS.include?(h) }
    end
  end
end
