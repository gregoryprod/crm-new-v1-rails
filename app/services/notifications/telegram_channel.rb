require "net/http"

module Notifications
  # Telegram Bot API `sendMessage` to the administrators' chat over plain HTTPS (no SDK, no
  # webhook). Plain text without parse_mode, so lead data never needs escaping. The token
  # appears only in the request URL and is never returned, logged or stored.
  class TelegramChannel
    MAX_ERROR = 300
    MAX_TEXT = 4_096

    Result = Data.define(:ok, :error, :retry_after_seconds, :permanent) do
      def self.success = new(ok: true, error: nil, retry_after_seconds: nil, permanent: false)
      def self.failure(error, retry_after_seconds: nil, permanent: false) = new(ok: false, error:, retry_after_seconds:, permanent:)
    end

    attr_reader :name

    def initialize(bot_token:, chat_id:, api_base_url:, timeout_seconds:)
      @bot_token = bot_token
      @chat_id = chat_id
      @api_base_url = api_base_url
      @timeout_seconds = timeout_seconds
      @name = "telegram"
    end

    # Removes anything that looks like a bot token and control characters, then truncates.
    def self.redact(text, token)
      result = token.present? ? text.gsub(token, "[скрыто]") : text.dup
      result = result.gsub(/\d{3,20}:[A-Za-z0-9_-]{30,64}/, "[скрыто]")
      result = result.gsub(/[\p{Cc}\p{Cf}]+/, " ").strip
      result.length > MAX_ERROR ? "#{result[0, MAX_ERROR - 1]}…" : result
    end

    def send_message(text)
      uri = URI("#{@api_base_url}/bot#{@bot_token}/sendMessage")
      body = JSON.generate(chat_id: @chat_id, text: text[0, MAX_TEXT], link_preview_options: { is_disabled: true })
      begin
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = @timeout_seconds
        http.read_timeout = @timeout_seconds
        http.write_timeout = @timeout_seconds
        response = http.request(Net::HTTP::Post.new(uri, "content-type" => "application/json").tap { |r| r.body = body })
      rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout, Timeout::Error
        return fail("Telegram не ответил за #{@timeout_seconds} с")
      rescue StandardError
        # Network error messages may include the request URL with the token: class only.
        return fail("Telegram недоступен: сетевая ошибка")
      end

      # Redirects are never followed (fetch redirect: "error" in the previous app).
      return fail("Telegram недоступен: сетевая ошибка") if response.is_a?(Net::HTTPRedirection)
      parsed = begin
        JSON.parse(response.body.to_s)
      rescue JSON::ParserError
        nil
      end
      parsed = nil unless parsed.is_a?(Hash)
      ok_status = response.is_a?(Net::HTTPSuccess)
      return Result.success if ok_status && parsed && parsed["ok"] == true

      description = parsed && parsed["description"].is_a?(String) ? parsed["description"] : ""
      retry_after = parsed && parsed["parameters"].is_a?(Hash) ? parsed["parameters"]["retry_after"] : nil
      retry_after = retry_after.is_a?(Numeric) && retry_after.finite? && retry_after.positive? ? retry_after.ceil : nil
      status = ok_status ? "ответ без ok" : "HTTP #{response.code}"
      fail("Telegram #{status}#{description.empty? ? '' : ": #{description}"}", retry_after)
    end

    private

    def fail(error, retry_after = nil)
      Result.failure(self.class.redact(error, @bot_token), retry_after_seconds: retry_after)
    end
  end
end
