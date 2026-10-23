module Booking
  # Bearer receipt that lets the quiz book a slot for the lead it just created.
  # Only sha256(token) is stored; the token itself is an HMAC of the lead id.
  module Receipt
    module_function

    def token_hash(token)
      Digest::SHA256.hexdigest(token)
    end

    def token_for(lead_id)
      OpenSSL::HMAC.hexdigest("SHA256", AppEnv.server.auth_secret, "booking-receipt:#{lead_id}")
    end

    def expiry
      30.days.from_now
    end

    def issue(lead_id)
      ActiveRecord::Base.transaction do
        status = Lead.where(id: lead_id).pick(:status)
        next nil if status.nil? || status == "SPAM"
        token = token_for(lead_id)
        ActiveRecord::Base.connection.exec_insert(
          "INSERT INTO booking_receipts (lead_id, token_hash, expires_at) VALUES ($1, $2, $3) ON CONFLICT DO NOTHING",
          "Receipt Insert", [ lead_id, token_hash(token), expiry ]
        )
        receipt = BookingReceipt.find_by(lead_id:)
        receipt && receipt.expires_at > Time.current && receipt.token_hash == token_hash(token) ? token : nil
      end
    end

    def valid?(lead_id, token)
      receipt = BookingReceipt.find_by(lead_id:)
      return false if receipt.nil? || receipt.expires_at <= Time.current
      digest = token_hash(token)
      [ receipt.token_hash, receipt.legacy_token_hash ].any? do |hash|
        hash.is_a?(String) && hash.length == 64 && ActiveSupport::SecurityUtils.secure_compare(digest, hash)
      end
    end
  end
end
