module Api
  module Crm
    class LeadsController < ApiController
      # Staff-only lead list with the same filters as /crm/leads (status, from, to, source, q, page).
      def index
        require_staff
        query, invalid = Leads::Staff.parse_query(query_params)
        render_json(Leads::Staff.list_page(query).merge("invalid" => invalid))
      end

      def show
        require_staff
        card = Leads::Staff.card(params[:id])
        card ? render_json({ "lead" => card }) : render_error(404, "not_found")
      end

      # Status / assignee / comment; same-origin JSON only (CSRF), audited in one transaction.
      def update
        require_same_origin!
        staff = require_staff
        return render_error(415, "unsupported_media_type") unless json_content?
        body = read_json_body(8 * 1024)
        return render_error(413, "payload_too_large") if body.equal?(TooLarge)
        data, fields = Leads::Staff.parse_update(body)
        return render_json({ "error" => "invalid_request", "fields" => fields }, 400) unless data

        result = Leads::Staff.update(staff.user.id, params[:id], data)
        case result[:kind]
        when "not_found" then render_error(404, "not_found")
        when "invalid" then render_json({ "error" => "invalid_request", "fields" => result[:fields] }, 400)
        when "stale" then render_json({ "error" => "stale_version", "version" => result[:version] }, 409)
        else
          state = result[:state]
          render_json({ "result" => result[:kind],
                        "lead" => { "version" => state[:version], "status" => state[:status], "assigned_to" => state[:assigned_to], "comment" => state[:comment] } })
        end
      end

      private

      def failure_event = "crm.lead.request_failed"
    end
  end
end
