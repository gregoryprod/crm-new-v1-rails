# Server-rendered staff pages. Authentication is the same server session as the API;
# state-changing actions go through the JSON API (Origin-checked), so pages carry no forms
# that post to Rails itself except the logout form (also Origin-checked).
class ApplicationController < ActionController::Base
  class Unavailable < StandardError; end

  layout "application"

  # No query cache: claims, row locks (FOR UPDATE), INSERT/UPDATE … RETURNING and
  # clock_timestamp() reads must hit PostgreSQL every time, never a cached result.
  around_action { |_, action| ActiveRecord::Base.uncached(&action) }

  rescue_from StandardError do |error|
    raise error if error.is_a?(ActionController::RoutingError)
    LogEvent.error(failure_event, error)
    response.headers["Cache-Control"] = "no-store"
    render "shared/unavailable", status: :internal_server_error unless performed?
  end

  # A form older than the session (or a cross-site post) is refused without details.
  rescue_from ActionController::InvalidAuthenticityToken do
    redirect_back fallback_location: "/crm", status: :see_other, alert: "Форма устарела. Обнови страницу и повтори действие."
  end

  helper_method :current_user, :crm_time_zone

  private

  def failure_event = "crm.page.failed"

  def crm_time_zone = AppEnv.server.crm_time_zone

  def current_user = @staff&.user

  def page_session
    Auth::Service.session_user(cookies[SessionCookie.cookie_name])
  end

  # Redirects to /login without a valid session and to /crm without the role.
  def require_page_role(role = "ADMIN")
    response.headers["Cache-Control"] = "no-store"
    @staff = page_session
    return redirect_to("/login", status: :see_other) unless @staff
    redirect_to("/crm", status: :see_other) unless @staff.user.has_role?(role)
  end

  # Client IP only from a trusted reverse proxy; otherwise unknown (no per-IP limit).
  def client_ip
    return nil unless AppEnv.server.trust_proxy
    request.headers["X-Forwarded-For"].to_s.split(",").first.to_s.strip.presence || request.headers["X-Real-IP"].to_s.strip.presence
  end

  def not_found!
    render "shared/not_found", status: :not_found
  end
end
