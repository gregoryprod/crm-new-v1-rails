module Yclients
  # Errors whose message is safe to print: names a file/stage, never source content.
  class SourceError < StandardError; end
end
