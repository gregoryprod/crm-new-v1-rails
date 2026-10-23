module Api
  class AuthController < ApiController
    def login
      require_same_origin!
      return render_error(415, "unsupported_media_type") unless json_content?
      body = read_json_body(4 * 1024)
      return render_error(413, "payload_too_large") if body.equal?(TooLarge)
      email = body.is_a?(Hash) && body["email"].is_a?(String) ? body["email"].strip : nil
      password = body.is_a?(Hash) ? body["password"] : nil
      unless email&.length&.between?(1, 320) && password.is_a?(String) && password.length.between?(1, 256)
        return render_error(400, "invalid_request")
      end

      result = Auth::Service.login(email:, password:, ip: client_ip)
      unless result.ok
        return result.reason == "throttled" ?
          render_error(429, "too_many_attempts", "Retry-After" => result.retry_after_seconds.to_s) :
          render_error(401, "invalid_credentials")
      end
      cookies[SessionCookie.cookie_name] = SessionCookie.cookie_options(result.token, AppEnv.server.session_ttl_hours * 3600)
      render_json({ "user" => { "name" => result.user.name, "role" => result.user.role } })
    end

    # Plain form POST; revokes the server session and clears the cookie.
    def logout
      require_same_origin!
      name = SessionCookie.cookie_name
      Auth::Service.logout(cookies[name])
      cookies[name] = SessionCookie.cookie_options("", 0)
      response.headers["Cache-Control"] = "no-store"
      redirect_to "#{AppEnv.server.app_origin}/login", status: :see_other, allow_other_host: true
    end

    def session
      staff = require_staff
      user = staff.user
      render_json({ "user" => { "id" => user.id, "email" => user.email, "name" => user.name, "role" => user.role },
                    "expiresAt" => staff.expires_at })
    end
  end
end
