module CryptoHelpers
  module_function

  # Keyed hash with a purpose label, so one secret yields unrelated hashes per use.
  def keyed_hash(secret, purpose, value)
    Base64.urlsafe_encode64(OpenSSL::HMAC.digest("SHA256", secret, "#{purpose}\0#{value}"), padding: false)
  end

  def random_token(bytes = 32)
    Base64.urlsafe_encode64(SecureRandom.random_bytes(bytes), padding: false)
  end

  UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
  # RFC 9562 layout, as zod's z.uuid() accepts it (versions 1–8, variant 10xx).
  STRICT_UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

  def uuid?(value)
    value.is_a?(String) && (STRICT_UUID.match?(value) || value.match?(/\A0{8}-0{4}-0{4}-0{4}-0{12}\z|\Af{8}-f{4}-f{4}-f{4}-f{12}\z/i))
  end

  # Deterministic UUID for a source identity (same bytes as the Node legacyId()).
  def legacy_id(kind, id)
    bytes = Digest::SHA256.digest("vpc-legacy-v1:#{kind}:#{id}").bytes.first(16)
    bytes[6] = (bytes[6] & 15) | 80
    bytes[8] = (bytes[8] & 63) | 128
    hex = bytes.pack("C*").unpack1("H*")
    "#{hex[0, 8]}-#{hex[8, 4]}-#{hex[12, 4]}-#{hex[16, 4]}-#{hex[20, 12]}"
  end
end
