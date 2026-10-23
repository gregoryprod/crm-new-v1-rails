module Auth
  # Staff login with server-side sessions. Wrong password, unknown email and inactive
  # account all yield the same "invalid" outcome; attempts are counted before verification
  # for both the account and the IP, atomically in PostgreSQL.
  module Service
    LoginResult = Data.define(:ok, :reason, :token, :user, :expires_at, :retry_after_seconds)
    SessionUser = Data.define(:session_id, :expires_at, :user)

    module_function

    def normalize_email(email)
      email.strip.downcase
    end

    def hash_session_token(token)
      CryptoHelpers.keyed_hash(AppEnv.server.auth_secret, "session", token)
    end

    def throttle_key(kind, value)
      "#{kind}:#{CryptoHelpers.keyed_hash(AppEnv.server.auth_secret, "login-#{kind}", value)}"
    end

    def login(email:, password:, ip:)
      env = AppEnv.server
      email = normalize_email(email)
      email_key = throttle_key("email", email)

      delete_stale_login_attempts
      windows = [ [ email_key, env.login_max_attempts ] ]
      windows << [ throttle_key("ip", ip), env.login_ip_max_attempts ] if ip
      windows.each do |key, max|
        attempts, retry_after = register_login_attempt(key, env.login_window_minutes)
        return failure("throttled", retry_after) if attempts > max
      end

      user = User.find_by(email:)
      unless user
        Passwords.verify_against_dummy(password)
        return failure("invalid")
      end
      return failure("invalid") unless Passwords.verify(user.password_hash, password) && user.active

      LoginThrottle.where(key: email_key).delete_all
      token = CryptoHelpers.random_token
      expires_at = ActiveRecord::Base.connection.select_value(
        ApplicationRecord.sql(
          "INSERT INTO sessions (user_id, token_hash, expires_at) " \
          "VALUES (?, ?, now() + make_interval(hours => ?)) RETURNING expires_at",
          user.id, hash_session_token(token), env.session_ttl_hours
        )
      )
      LoginResult.new(ok: true, reason: nil, token:, user:, expires_at:, retry_after_seconds: nil)
    end

    def failure(reason, retry_after = nil)
      LoginResult.new(ok: false, reason:, token: nil, user: nil, expires_at: nil, retry_after_seconds: retry_after)
    end

    # Valid = not revoked, not expired (database clock) and owned by an active user.
    def session_user(token)
      return nil if token.blank? || token.length > 128
      row = StaffSession.joins(:user)
        .where(token_hash: hash_session_token(token), revoked_at: nil, users: { active: true })
        .where("sessions.expires_at > now()")
        .pick("sessions.id", "sessions.expires_at", "users.id")
      return nil unless row
      SessionUser.new(session_id: row[0], expires_at: row[1], user: User.find(row[2]))
    end

    def logout(token)
      return if token.blank? || token.length > 128
      StaffSession.where(token_hash: hash_session_token(token), revoked_at: nil).update_all("revoked_at = now()")
    end

    # Counts an attempt in a fixed window *before* the password is checked, so concurrent
    # bursts cannot all slip past the limit. Returns [attempts, retry_after_seconds].
    def register_login_attempt(key, window_minutes)
      expired = "login_throttle.window_started_at <= now() - make_interval(mins => #{Integer(window_minutes)})"
      row = ActiveRecord::Base.connection.select_rows(ApplicationRecord.sql(<<~SQL, key)).first
        INSERT INTO login_throttle (key, attempts, window_started_at) VALUES (?, 1, now())
        ON CONFLICT (key) DO UPDATE SET
          attempts = CASE WHEN #{expired} THEN 1 ELSE login_throttle.attempts + 1 END,
          window_started_at = CASE WHEN #{expired} THEN now() ELSE login_throttle.window_started_at END,
          updated_at = now()
        RETURNING attempts,
          GREATEST(1, CEIL(EXTRACT(EPOCH FROM (window_started_at + make_interval(mins => #{Integer(window_minutes)}) - now()))))::int
      SQL
      row.map(&:to_i)
    end

    def delete_stale_login_attempts
      LoginThrottle.where("window_started_at < now() - interval '1 day'").delete_all
    end
  end
end
