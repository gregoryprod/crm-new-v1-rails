module Api
  # Public booking used by the quiz: catalog, free slots and the reservation itself.
  class BookingController < ApiController
    rescue_from Calendar::Error, Booking::Error do |error|
      render_error(error.status, error.code)
    end
    # The exclusion constraint / unique index are the final guard against double booking.
    rescue_from ActiveRecord::StatementInvalid do |error|
      if %w[23P01 23505].include?(LogEvent.sqlstate(error))
        render_error(409, "slot_unavailable")
      else
        LogEvent.error(failure_event, error)
        render_error(500, "internal_error")
      end
    end

    def catalog
      Booking::Service.admit_public_read
      render_json(Booking::Service.catalog)
    end

    def slots
      q = query_params
      doctor_id = Booking::Service.resolve_id("doctor", q["doctorId"])
      service_id = Booking::Service.resolve_id("service", q["serviceId"])
      valid = (q.keys - %w[doctorId serviceId day]).empty? && doctor_id && service_id && Calendar::Slots.valid_day?(q["day"])
      return render_error(400, "invalid_request") unless valid
      Booking::Service.admit_public_read
      service_doctor = DoctorService.where(id: service_id).pick(:doctor_id)
      return render_error(400, "invalid_request") unless service_doctor && service_doctor == doctor_id
      render_json(Calendar::Service.slots(service_id:, day: q["day"]))
    end

    def create
      require_same_origin!
      return render_error(415, "unsupported_media_type") unless json_content?(exact: true)
      body = read_json_body(8192)
      return render_error(413, "payload_too_large") if body.equal?(TooLarge)
      command = Booking::Service.parse_command(body)
      return render_error(400, "invalid_request") unless command
      render_json(Booking::Service.book(command))
    end

    private

    def failure_event = "booking.request_failed"
  end
end
