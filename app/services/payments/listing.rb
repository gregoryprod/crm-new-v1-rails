module Payments
  # Actual service receipts; inclusive Moscow calendar days, never quoted prices.
  module Listing
    KEYS = %w[id bookingId clientId patientId doctorId serviceId title amountCents currency method paidAt
              actorId note createdAt updatedAt clientFirstName clientLastName doctorName].freeze

    module_function

    # Returns the parsed filter or nil when invalid (strict, from ≤ to).
    def parse(params)
      return nil unless (params.keys - %w[from to doctorId clientId]).empty?
      out = {}
      %w[from to].each do |key|
        next unless params.key?(key)
        return nil unless Calendar::Slots.valid_day?(params[key])
        out[key] = params[key]
      end
      %w[doctorId clientId].each do |key|
        next unless params.key?(key)
        return nil unless CryptoHelpers.uuid?(params[key])
        out[key] = params[key]
      end
      return nil if out["from"] && out["to"] && out["from"] > out["to"]
      out
    end

    def list(filter = {})
      scope = Payment.joins("JOIN clients ON clients.id = payments.client_id JOIN doctors ON doctors.id = payments.doctor_id")
      scope = scope.where("payments.paid_at >= ?", Calendar::Slots.day_range(filter["from"]).start) if filter["from"]
      scope = scope.where("payments.paid_at < ?", Calendar::Slots.day_range(filter["to"]).end) if filter["to"]
      scope = scope.where(doctor_id: filter["doctorId"]) if filter["doctorId"]
      scope = scope.where(client_id: filter["clientId"]) if filter["clientId"]
      scope.order("payments.paid_at", "payments.id").pluck(
        "payments.id", :booking_id, "payments.client_id", :patient_id, "payments.doctor_id", :service_id, :title,
        :amount_cents, :currency, :method, :paid_at, :actor_id, :note, "payments.created_at", "payments.updated_at",
        "clients.first_name", "clients.last_name", "doctors.name"
      ).map { |values| KEYS.zip(values).to_h }
    end
  end
end
