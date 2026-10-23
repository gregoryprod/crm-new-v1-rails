# Staff login form (the JSON endpoint /api/auth/login stays for scripts and smoke tests).
class SessionsController < ApplicationController
  MESSAGES = {
    "invalid_request" => "Введите email и пароль.",
    "invalid" => "Неверный email или пароль.",
    "throttled" => "Слишком много попыток входа. Попробуйте позже."
  }.freeze

  def create
    response.headers["Cache-Control"] = "no-store"
    email = params[:email].to_s.strip
    password = params[:password].to_s
    unless email.length.between?(1, 320) && password.length.between?(1, 256)
      return render_login("invalid_request", :bad_request)
    end
    result = Auth::Service.login(email:, password:, ip: client_ip)
    unless result.ok
      response.headers["Retry-After"] = result.retry_after_seconds.to_s if result.reason == "throttled"
      return render_login(result.reason, result.reason == "throttled" ? :too_many_requests : :unauthorized)
    end
    cookies[SessionCookie.cookie_name] = SessionCookie.cookie_options(result.token, AppEnv.server.session_ttl_hours * 3600)
    redirect_to "/crm", status: :see_other
  end

  private

  def render_login(reason, status)
    @error = MESSAGES.fetch(reason)
    @email = params[:email].to_s
    render "pages/login", status:
  end
end
