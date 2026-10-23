module Phone
  RAW_PHONE = /\A[0-9+()\-.\s]{5,32}\z/

  module_function

  # User input → E.164 with RU as the default region ("8 999…" → "+7999…"). Full
  # libphonenumber metadata checks the number plan, not only the length. Invalid → nil.
  def normalize(raw)
    return nil unless raw.is_a?(String)
    value = raw.strip
    return nil unless RAW_PHONE.match?(value)
    phone = Phonelib.parse(value, "RU")
    phone.valid? ? phone.e164 : nil
  end

  # "+79991234567" → "+7 999 123-45-67" for RU numbers; others stay E.164.
  def format(e164)
    return "Не указан" if e164.blank?
    match = /\A\+7(\d{3})(\d{3})(\d{2})(\d{2})\z/.match(e164)
    match ? "+7 #{match[1]} #{match[2]}-#{match[3]}-#{match[4]}" : e164
  end
end
