module Api
  module Crm
    class CalendarController < ApiController
      rescue_from Calendar::Error do |error|
        render_error(error.status, error.code)
      end

      def show
        require_staff
        q = query_params
        return render_error(400, "invalid_request") unless (q.keys - %w[day view doctorId]).empty? && Calendar::Slots.valid_day?(q["day"])
        view = q.fetch("view", "day")
        return render_error(400, "invalid_request") unless %w[day week].include?(view)
        return render_error(400, "invalid_request") if q.key?("doctorId") && !CryptoHelpers.uuid?(q["doctorId"])
        render_json(Calendar::Service.snapshot(day: q["day"], view:, doctor_id: q["doctorId"]))
      end

      def create
        require_same_origin!
        staff = require_staff
        return render_error(415, "unsupported_media_type") unless json_content?(exact: true)
        body = read_json_body(16 * 1024)
        return render_error(413, "payload_too_large") if body.equal?(TooLarge)
        command = Calendar::Commands.parse(body)
        return render_error(400, "invalid_request") unless command
        render_json(Calendar::Service.execute(staff.user.id, command))
      end

      def slots
        require_staff
        q = query_params
        valid = (q.keys - %w[day serviceId excludeId]).empty? && Calendar::Slots.valid_day?(q["day"]) &&
          CryptoHelpers.uuid?(q["serviceId"]) && (!q.key?("excludeId") || CryptoHelpers.uuid?(q["excludeId"]))
        return render_error(400, "invalid_request") unless valid
        render_json(Calendar::Service.slots(day: q["day"], service_id: q["serviceId"], exclude_id: q["excludeId"]))
      end

      def patients
        require_staff
        q = query_params["q"].to_s.strip
        return render_error(400, "invalid_request") if q.length < 2 || q.length > 100 || query_params.length != 1
        escaped = q.gsub(/[\\%_]/) { |c| "\\#{c}" }
        like = "%#{escaped}%"
        rows = Patient.joins(:client)
          .where("clients.last_name ILIKE :l OR clients.first_name ILIKE :l OR clients.phone ILIKE :l OR patients.name ILIKE :l", l: like)
          .order("clients.last_name", "patients.id").limit(25)
          .pluck("patients.id", "clients.id", "patients.name", "patients.species", "clients.first_name", "clients.last_name", "clients.phone")
          .map { |values| %w[id clientId name species firstName lastName phone].zip(values).to_h }
        render_json({ "patients" => rows })
      end

      def appointment
        require_staff
        return render_error(404, "not_found") unless CryptoHelpers.uuid?(params[:id])
        booking = Calendar::Service.booking_by_id(params[:id])
        booking ? render_json({ "booking" => booking }) : render_error(404, "not_found")
      end

      private

      def failure_event = "calendar.request_failed"
    end
  end
end
