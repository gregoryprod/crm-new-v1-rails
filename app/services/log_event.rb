# One-line structured JSON logs. Fields are limited to identifiers, flags, counters and
# error classes: names, phones, payloads and driver messages never reach stdout/stderr.
module LogEvent
  module_function

  def info(event, fields = {})
    write($stdout, "info", event, fields)
  end

  def warn(event, fields = {})
    write($stderr, "warn", event, fields)
  end

  # Only the error class and SQLSTATE, never the message (it may contain values).
  def error(event, error, fields = {})
    write($stderr, "error", event, { error: error_name(error), code: sqlstate(error) }.merge(fields))
    # Development and tests only: the backtrace (never written in production).
    Rails.logger.debug { error.full_message(highlight: false) } if !Rails.env.production? && error.is_a?(Exception)
  end

  def error_name(error)
    error.is_a?(Exception) ? error.class.name.demodulize : error.class.name
  end

  def sqlstate(error)
    current = error
    3.times do
      break if current.nil?
      code = current.respond_to?(:result) && current.result.respond_to?(:error_field) ? current.result.error_field(PG::PG_DIAG_SQLSTATE) : nil
      return code if code
      current = current.respond_to?(:cause) ? current.cause : nil
    end
    nil
  end

  def write(io, level, event, fields)
    return if Rails.env.test? && ENV["LOG_EVENTS"].blank?
    io.puts(JSON.generate({ level:, event: }.merge(fields)))
  end
end
