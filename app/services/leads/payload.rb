module Leads
  # Request fields of POST /api/leads. Unknown keys are dropped and never stored; errors
  # report field names only (from a fixed list), never the submitted values.
  module Payload
    FIELDS = %w[last_name first_name phone species consent_pd consent_marketing quiz_version
                idempotency_key utm page_url website].freeze
    UTM_KEYS = %w[source medium campaign content term].freeze
    BUSINESS_FIELDS = %w[last_name first_name phone species consent_pd consent_marketing quiz_version].freeze

    MAX_UTM_LENGTH = 100
    MAX_PAGE_URL_INPUT = 2048
    MAX_PAGE_URL = 500

    EMAIL_LIKE = %r{[^\s@/]+@[^\s@/]+\.[^\s@/]+}
    DIGIT_RUN = /\+?\d[\d[:space:]().-]{5,}\d/

    Input = Data.define(:last_name, :first_name, :phone, :phone_raw, :species, :consent_marketing,
                        :quiz_version, :idempotency_key, :utm, :page_url, :honeypot)
    Result = Data.define(:ok, :lead, :fields)

    module_function

    def parse(body)
      return Result.new(ok: false, lead: nil, fields: []) unless body.is_a?(Hash)

      invalid = []
      field = ->(name) { body.key?(name) ? body[name] : :missing }
      last_name = person_name(field.("last_name")) || invalid.push("last_name") && nil
      first_name = person_name(field.("first_name")) || invalid.push("first_name") && nil
      phone = phone_field(field.("phone")) || invalid.push("phone") && nil
      species = species_field(field.("species")) || invalid.push("species") && nil
      invalid << "consent_pd" unless field.("consent_pd") == true
      marketing = field.("consent_marketing")
      marketing = false if marketing == :missing
      invalid << "consent_marketing" unless [ true, false ].include?(marketing)
      quiz_version = field.("quiz_version")
      invalid << "quiz_version" unless quiz_version.is_a?(String) && quiz_version.match?(/\A[\w.:-]{1,64}\z/)
      key = field.("idempotency_key")
      invalid << "idempotency_key" unless key.is_a?(String) && key.match?(/\A[A-Za-z0-9_-]{16,128}\z/)
      return Result.new(ok: false, lead: nil, fields: invalid.uniq.sort) if invalid.any?

      website = field.("website")
      Result.new(ok: true, fields: [], lead: Input.new(
        last_name:, first_name:, phone: phone[:e164], phone_raw: phone[:raw], species:,
        consent_marketing: marketing, quiz_version:, idempotency_key: key,
        utm: sanitize_utm(field.("utm")), page_url: sanitize_page_url(field.("page_url")),
        honeypot: honeypot_filled?(website == :missing ? nil : website)
      ))
    end

    def person_name(value)
      return nil unless value.is_a?(String) && value.length <= 400
      cleaned = TextRules.clean(value)
      return nil if cleaned.empty? || cleaned.length > 100
      cleaned if !TextRules::CONTROL.match?(cleaned) && TextRules::LETTER.match?(cleaned)
    end

    def species_field(value)
      return nil unless value.is_a?(String) && value.length <= 200
      cleaned = TextRules.clean(value)
      return nil if cleaned.empty? || cleaned.length > 50
      cleaned if !TextRules::CONTROL.match?(cleaned) && TextRules::LETTER.match?(cleaned)
    end

    def phone_field(value)
      return nil unless value.is_a?(String) && value.length <= 64
      e164 = Phone.normalize(value)
      e164 && { e164:, raw: TextRules.clean(value) }
    end

    # An email or a digit run that is a valid phone number. Plain numeric IDs (e.g. ad
    # campaign ids) are not phone numbers and stay.
    def looks_personal?(value)
      return true if EMAIL_LIKE.match?(value)
      value.scan(DIGIT_RUN).any? do |match|
        digits = match.gsub(/[^\d+]/, "")
        Phone.normalize(digits) || Phone.normalize("+#{digits.delete_prefix('+')}")
      end
    end

    # Allow-listed UTM keys only; control characters, overlong or personal-looking values are dropped.
    def sanitize_utm(value)
      return nil unless value.is_a?(Hash)
      utm = {}
      UTM_KEYS.each do |key|
        raw = value[key]
        next unless raw.is_a?(String)
        cleaned = TextRules.clean(raw)
        next if cleaned.empty? || cleaned.length > MAX_UTM_LENGTH || TextRules::CONTROL.match?(cleaned) || looks_personal?(cleaned)
        utm[key] = cleaned
      end
      utm.empty? ? nil : utm
    end

    # Keeps only scheme, host and path: credentials, query and fragment (where forms and
    # trackers leak personal data) are removed; a path that looks personal is cut to "/".
    def sanitize_page_url(value)
      return nil unless value.is_a?(String) && value.length <= MAX_PAGE_URL_INPUT
      uri = URI.parse(value.strip)
      return nil unless %w[http https].include?(uri.scheme) && uri.host.present?
      default_port = uri.scheme == "https" ? 443 : 80
      origin = "#{uri.scheme}://#{uri.host.downcase}#{uri.port == default_port ? '' : ":#{uri.port}"}"
      path = uri.path.presence || "/"
      decoded = URI::RFC2396_PARSER.unescape(path).force_encoding(Encoding::UTF_8)
      decoded = path unless decoded.valid_encoding?
      path = "/" if TextRules::CONTROL.match?(decoded) || looks_personal?(decoded)
      cleaned = "#{origin}#{path}"
      return cleaned if cleaned.length <= MAX_PAGE_URL
      origin.length <= MAX_PAGE_URL ? "#{origin}/" : nil
    rescue URI::InvalidURIError, ArgumentError
      nil
    end

    def honeypot_filled?(value)
      return false if value.nil? || value == false
      return value.strip != "" if value.is_a?(String)
      true
    end

    # The stored `raw_payload`: only known, cleaned fields; the honeypot as a flag.
    def raw_payload(lead)
      {
        "last_name" => lead.last_name, "first_name" => lead.first_name, "phone" => lead.phone,
        "phone_raw" => lead.phone_raw, "species" => lead.species, "consent_pd" => true,
        "consent_marketing" => lead.consent_marketing, "quiz_version" => lead.quiz_version,
        "utm" => lead.utm, "page_url" => lead.page_url, "honeypot" => lead.honeypot
      }
    end

    # Same idempotency key + same business data and consent decisions = replay. Phone
    # formatting, UTM, page URL and the honeypot do not matter.
    def same_submission?(stored, lead)
      return false unless stored.is_a?(Hash)
      current = raw_payload(lead)
      BUSINESS_FIELDS.all? { |name| stored[name] == current[name] && stored[name].class == current[name].class }
    end
  end
end
