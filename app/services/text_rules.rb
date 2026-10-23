# Text checks shared by the public intake and staff filters (JavaScript \p{Cc}\p{Cf}, \p{L}).
module TextRules
  CONTROL = /[\p{Cc}\p{Cf}]/
  LETTER = /\p{L}/

  module_function

  # NFC, trimmed, inner whitespace collapsed (JavaScript \s semantics).
  def clean(value)
    value.unicode_normalize(:nfc).gsub(/[[:space:]﻿]+/, " ").strip
  end

  # Case-insensitive regex that does not depend on the database locale (lower()/ILIKE do not
  # fold Cyrillic under the C locale): every letter becomes a class of its cases, "е"
  # matches "ё", everything else is escaped. User input never reaches the regex unescaped.
  def case_insensitive_regex(text)
    text.each_char.map do |char|
      lower = char.downcase
      next "[еЕёЁ]" if lower == "е" || lower == "ё"
      upper = char.upcase
      next "[#{lower}#{upper}]" if lower != upper
      char.match?(%r{[\\^$.*+?()\[\]{}|/-]}) ? "\\#{char}" : char
    end.join
  end
end
