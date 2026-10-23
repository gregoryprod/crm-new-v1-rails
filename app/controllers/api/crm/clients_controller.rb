module Api
  module Crm
    class ClientsController < ApiController
      def index
        require_staff
        query = Clients::Directory.parse_query(query_params)
        return render_error(400, "invalid_request") unless query
        render_json(Clients::Directory.list(query))
      end

      def show
        require_staff
        details = Clients::Directory.details(params[:id])
        details ? render_json(details) : render_error(404, "not_found")
      end

      def create_patient
        require_same_origin!
        staff = require_staff
        return render_error(404, "not_found") unless CryptoHelpers.uuid?(params[:id])
        return render_error(415, "unsupported_media_type") unless json_content?(exact: true)
        body = read_json_body(4096)
        return render_error(413, "payload_too_large") if body.equal?(TooLarge)
        input = Clients::Directory.parse_patient(body)
        return render_error(400, "invalid_request") unless input
        kind, id = Clients::Directory.create_confirmed_patient(staff.user.id, params[:id], input)
        return render_json({ "id" => id }) if kind == :saved
        render_error(kind == :not_found ? 404 : 409, kind.to_s)
      end

      private

      def failure_event = "clients.request_failed"
    end
  end
end
