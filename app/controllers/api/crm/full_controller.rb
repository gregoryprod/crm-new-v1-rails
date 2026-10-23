module Api
  module Crm
    # JSON API of the restored workspace (public/full-crm).
    class FullController < ApiController
      rescue_from FullCrm::WorkError do |error|
        render_error(error.status, error.message)
      end

      def show
        require_staff
        return render_error(400, "invalid_request") unless (query_params.keys - %w[resource key]).empty?
        render_json(FullCrm::Service.query(query_params["resource"].to_s, query_params["key"]))
      end

      def write
        require_same_origin!
        staff = require_staff
        return render_error(415, "unsupported_media_type") unless json_content?(exact: true)
        body = read_json_body(32_768)
        return render_error(413, "payload_too_large") if body.equal?(TooLarge)
        render_json(FullCrm::Service.command(query_params["resource"].to_s, body, staff.user.id))
      end

      # The restored UI is isolated from the app CSS, with same-origin framing only.
      def assets
        require_staff
        response.headers.merge!(
          "Cache-Control" => "private, no-store", "Vary" => "Cookie", "X-Frame-Options" => "SAMEORIGIN",
          "Content-Security-Policy" => "frame-ancestors 'self'; base-uri 'self'; form-action 'self'; object-src 'none'"
        )
        render body: Rails.public_path.join("full-crm/index.html").read, content_type: "text/html; charset=utf-8"
      end

      private

      def failure_event = "full_crm.failed"
      def internal_error_code = "Не удалось выполнить операцию"

      def require_staff(role = "ADMIN")
        return super unless action_name == "assets"
        session = Auth::Service.session_user(cookies[SessionCookie.cookie_name])
        if session.nil? || !session.user.has_role?(role)
          response.headers["Cache-Control"] = "no-store"
          render plain: "Войди в CRM, чтобы открыть рабочее пространство.", status: session ? 403 : 401
          raise Halt
        end
        session
      end
    end
  end
end
