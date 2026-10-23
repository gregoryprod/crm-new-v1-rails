# Validated environment configuration, split by consumer like the previous zod schemas:
# the web app (server), public lead intake (leads), the notification worker and the owner
# seed. Each part is validated lazily, so a missing part disables only its feature.
# Error descriptions name variables and rules, never values.
module AppEnv
  class Error < StandardError
    attr_reader :issues

    def initialize(issues)
      @issues = issues
      super("Некорректная конфигурация окружения: #{issues.join('; ')}")
    end
  end

  LOOPBACK_HOSTS = %w[localhost 127.0.0.1 [::1]].freeze
  COMMON_PASSWORDS = %w[
    password password123 admin admin123 administrator changeme change-me
    qwerty qwerty123 12345678 123456789 1234567890 letmein welcome
    owner vetpetcare secret default
  ].to_set.freeze

  Server = Data.define(
    :database_url, :app_origin, :auth_secret, :session_ttl_hours, :login_max_attempts,
    :login_ip_max_attempts, :login_window_minutes, :trust_proxy, :crm_time_zone
  )
  Leads = Data.define(
    :allowed_origins, :consent_pd_version, :consent_marketing_version,
    :ip_max_per_window, :global_max_per_window, :window_minutes
  )
  Notifications = Data.define(
    :telegram_bot_token, :telegram_admin_chat_id, :telegram_api_base_url,
    :telegram_timeout_seconds, :worker_poll_seconds
  )
  OwnerSeed = Data.define(:email, :name, :password)

  class << self
    def server
      @server ||= parse_server(ENV)
    end

    def leads
      @leads ||= parse_leads(ENV)
    end

    def reset!
      @server = nil
      @leads = nil
    end

    def parse_server(source)
      reader = Reader.new(source)
      config = Server.new(
        database_url: reader.database_url("DATABASE_URL"),
        app_origin: reader.origin("APP_ORIGIN"),
        auth_secret: reader.string("AUTH_SECRET", min: 32, message: "минимум 32 символа"),
        session_ttl_hours: reader.integer("SESSION_TTL_HOURS", default: 12, min: 1, max: 24 * 30),
        login_max_attempts: reader.integer("LOGIN_MAX_ATTEMPTS", default: 5, min: 1, max: 100),
        login_ip_max_attempts: reader.integer("LOGIN_IP_MAX_ATTEMPTS", default: 50, min: 1, max: 10_000),
        login_window_minutes: reader.integer("LOGIN_WINDOW_MINUTES", default: 15, min: 1, max: 24 * 60),
        trust_proxy: reader.flag("TRUST_PROXY"),
        crm_time_zone: reader.time_zone("CRM_TIME_ZONE", default: "Europe/Moscow")
      )
      reader.finish!
      config
    end

    def parse_leads(source)
      reader = Reader.new(source)
      config = Leads.new(
        allowed_origins: reader.origin_list("LEADS_ALLOWED_ORIGINS"),
        consent_pd_version: reader.document_version("CONSENT_PD_VERSION"),
        consent_marketing_version: reader.document_version("CONSENT_MARKETING_VERSION"),
        ip_max_per_window: reader.integer("LEADS_IP_MAX_PER_WINDOW", default: 10, min: 1, max: 1_000),
        global_max_per_window: reader.integer("LEADS_GLOBAL_MAX_PER_WINDOW", default: 300, min: 1, max: 100_000),
        window_minutes: reader.integer("LEADS_WINDOW_MINUTES", default: 60, min: 1, max: 24 * 60)
      )
      reader.finish!
      config
    end

    # Read only by the notification worker: the web app never needs the bot token.
    def parse_notifications(source)
      reader = Reader.new(source)
      config = Notifications.new(
        telegram_bot_token: reader.pattern(
          "TELEGRAM_BOT_TOKEN", /\A\d{3,20}:[A-Za-z0-9_-]{30,64}\z/,
          "ожидается токен вида <число>:<ключ> от @BotFather", strip: true
        ),
        telegram_admin_chat_id: reader.pattern(
          "TELEGRAM_ADMIN_CHAT_ID", /\A-?\d{1,20}\z|\A@[A-Za-z][A-Za-z0-9_]{4,31}\z/,
          "числовой ID чата или @имя канала", strip: true
        ),
        telegram_api_base_url: reader.origin("TELEGRAM_API_BASE_URL", default: "https://api.telegram.org"),
        telegram_timeout_seconds: reader.integer("TELEGRAM_TIMEOUT_SECONDS", default: 10, min: 1, max: 60),
        worker_poll_seconds: reader.integer("WORKER_POLL_SECONDS", default: 5, min: 1, max: 300)
      )
      reader.finish!
      config
    end

    def parse_owner_seed(source)
      reader = Reader.new(source)
      email = reader.email("OWNER_EMAIL")
      name = reader.string("OWNER_NAME", default: "Владелец", strip: true, min: 1, max: 200)
      password = reader.string("OWNER_PASSWORD", min: 12, max: 256, message: "минимум 12 символов")
      if password && COMMON_PASSWORDS.include?(password.downcase)
        reader.issue("OWNER_PASSWORD", "стандартный или словарный пароль запрещен")
      end
      reader.finish!
      OwnerSeed.new(email:, name:, password:)
    end
  end

  # Collects every issue before failing, like zod's safeParse.
  class Reader
    def initialize(source)
      @source = source
      @issues = []
    end

    def issue(name, message)
      @issues << "#{name}: #{message}"
      nil
    end

    def finish!
      raise Error.new(@issues) if @issues.any?
    end

    def raw(name)
      value = @source[name]
      value.nil? || value == "" ? nil : value
    end

    def string(name, default: nil, min: nil, max: nil, strip: false, message: nil)
      value = raw(name) || default
      return issue(name, "обязательное значение") if value.nil?
      value = value.strip if strip
      return issue(name, message || "минимум #{min} символов") if min && value.length < min
      return issue(name, message || "максимум #{max} символов") if max && value.length > max
      value
    end

    def pattern(name, regex, message, strip: false)
      value = raw(name)
      return issue(name, "обязательное значение") if value.nil?
      value = value.strip if strip
      regex.match?(value) ? value : issue(name, message)
    end

    def integer(name, default:, min:, max:)
      value = raw(name)
      return default if value.nil?
      number = Integer(value.strip, 10, exception: false)
      return issue(name, "ожидается целое число от #{min} до #{max}") if number.nil? || number < min || number > max
      number
    end

    def flag(name)
      value = raw(name) || "false"
      return issue(name, "ожидается true, false, 1 или 0") unless %w[true false 1 0].include?(value)
      %w[true 1].include?(value)
    end

    def database_url(name)
      value = raw(name)
      return issue(name, "требуется postgresql:// URL") unless value&.match?(%r{\Apostgres(ql)?://.+})
      value
    end

    def origin(name, default: nil)
      value = raw(name) || default
      return issue(name, "обязательное значение") if value.nil?
      self.class.normalize_origin(value) || issue(name, "должен быть origin без пути, query и fragment; http допускается только для localhost/127.0.0.1")
    end

    def origin_list(name)
      value = raw(name)
      return issue(name, "нужен хотя бы один origin") if value.nil?
      items = value.split(",").map(&:strip).reject(&:empty?)
      return issue(name, "нужен хотя бы один origin") if items.empty?
      return issue(name, "не больше 20 origin") if items.length > 20
      origins = items.map do |item|
        origin = self.class.normalize_origin(item)
        host = origin && URI(origin).host
        unless origin && (host.match?(/\A[a-z0-9.-]+\z/) || host.match?(/\A\[[0-9a-f:.]+\]\z/))
          return issue(name, "только точный origin без *")
        end
        origin
      end
      origins.uniq
    end

    def document_version(name)
      value = raw(name)&.strip
      return issue(name, "обязательное значение") if value.nil? || value.empty?
      return issue(name, "максимум 64 символа") if value.length > 64
      value.match?(/\A[\w.:-]+\z/) ? value : issue(name, "только буквы, цифры и . _ : -")
    end

    def time_zone(name, default:)
      value = raw(name) || default
      TZInfo::Timezone.get(value)
      value
    rescue TZInfo::InvalidTimezoneIdentifier
      issue(name, "неизвестный часовой пояс IANA")
    end

    def email(name)
      value = raw(name)&.strip&.downcase
      return issue(name, "обязательное значение") if value.nil?
      value.match?(/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/) ? value : issue(name, "некорректный email")
    end

    # Origin of an http(s) URL without path, query or fragment; http only for loopback.
    def self.normalize_origin(value)
      uri = URI.parse(value)
      return nil unless %w[http https].include?(uri.scheme) && uri.host.present?
      return nil if uri.userinfo || uri.query || uri.fragment || !(uri.path.empty? || uri.path == "/")
      host = uri.host.downcase
      return nil unless uri.scheme == "https" || LOOPBACK_HOSTS.include?(host)
      default_port = uri.scheme == "https" ? 443 : 80
      port = uri.port == default_port ? "" : ":#{uri.port}"
      "#{uri.scheme}://#{host}#{port}"
    rescue URI::InvalidURIError
      nil
    end
  end
end
