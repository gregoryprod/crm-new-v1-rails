require "resolv"

module Leads
  # Fixed-window admission for public endpoints, atomic across processes (rate_limits table).
  module Throttle
    GLOBAL_KEY = "lead:global"
    IP_PREFIX = "lead:ip:"

    Result = Data.define(:limited, :scope, :retry_after_seconds)
    ADMITTED = Result.new(limited: false, scope: nil, retry_after_seconds: nil)

    module_function

    # A syntactically valid IP from the trusted proxy, or nil (garbage is treated as unknown).
    def valid_ip(ip)
      return nil if ip.blank?
      value = ip.strip
      address = value.split("%").first.to_s
      ip_version(address) ? value : nil
    end

    def ip_version(address)
      return 4 if address.match?(/\A#{Resolv::IPv4::Regex}\z/o) && address.split(".").none? { |p| p.length > 1 && p.start_with?("0") }
      return 6 if address.match?(/\A#{Resolv::IPv6::Regex}\z/o)
      nil
    end

    # IPv4 as is; IPv6 by /64 (one subscriber usually owns a whole /64).
    def rate_limit_subject(ip)
      address = ip.split("%").first.to_s.downcase
      return address if ip_version(address) == 4
      return address[7..] if address.start_with?("::ffff:") && ip_version(address[7..]) == 4
      head, tail = address.split("::", 2)
      head ||= ""
      width = ->(part) { part.include?(".") ? 2 : 1 }
      head_groups = head.empty? ? [] : head.split(":")
      tail_groups = tail.nil? || tail.empty? ? [] : tail.split(":")
      used = (head_groups + tail_groups).sum { |part| width.(part) }
      groups = tail.nil? ? head_groups : head_groups + Array.new([ 0, 8 - used ].max, "0") + tail_groups
      prefix = groups.first(4).map { |group| group.match?(/\A[0-9a-f]{1,4}\z/) ? group.to_i(16).to_s(16) : "0" }
      "#{prefix.join(':')}::/64"
    end

    # Admits one new submission or rejects it. Must run inside the intake transaction after
    # the idempotency key lock and re-check (replays never get here).
    #
    # The global window row is locked FOR UPDATE first and held until the transaction ends,
    # so every admission decision and its counter changes are serialised in PostgreSQL.
    # Expiry is judged by the database clock read after each lock is acquired:
    # - a global rejection writes nothing (no per-IP row is created);
    # - a per-IP rejection writes nothing (the global quota is not spent);
    # - an admission increments the per-IP and the global window together; a rollback
    #   rolls both back with the lead.
    def admit(ip, secret:, ip_max:, global_max:, window_minutes:, namespace: nil)
      global_key = namespace ? "#{namespace}:global" : GLOBAL_KEY
      ip_prefix = namespace ? "#{namespace}:ip:" : IP_PREFIX
      ensure_window(global_key, window_minutes)
      raise "global rate-limit window missing" unless lock_window(global_key)
      # Read the clock only now: the lock above may have waited past the end of the window.
      clock = admission_clock
      hits, retry_after = read_window(global_key, clock)
      raise "global rate-limit window missing" if hits.nil?
      return Result.new(limited: true, scope: "global", retry_after_seconds: retry_after) if hits >= global_max

      if ip
        ip_key = "#{ip_prefix}#{CryptoHelpers.keyed_hash(secret, 'lead-rate-ip', rate_limit_subject(ip))}"
        # Normally uncontended (all writers hold the global lock); if it waits, take a new clock.
        ip_clock = lock_window(ip_key) ? admission_clock : clock
        ip_hits, ip_retry = read_window(ip_key, ip_clock)
        return Result.new(limited: true, scope: "ip", retry_after_seconds: ip_retry) if ip_hits && ip_hits >= ip_max
        bump_window(ip_key, window_minutes, ip_clock)
      end
      bump_window(global_key, window_minutes, clock)
      delete_expired_windows(ip_prefix, clock)
      ADMITTED
    end

    def connection
      ActiveRecord::Base.connection
    end

    def ensure_window(key, window_minutes)
      connection.exec_update(<<~SQL, "RateLimit Ensure", [ key, window_minutes ])
        INSERT INTO rate_limits (key, hits, expires_at)
        VALUES ($1, 0, clock_timestamp() + make_interval(mins => $2::int))
        ON CONFLICT (key) DO NOTHING
      SQL
    end

    # Row-locks a window until the transaction ends. Deliberately returns no values:
    # anything computed in this statement would be evaluated before the wait.
    def lock_window(key)
      connection.select_rows(ApplicationRecord.sql("SELECT id FROM rate_limits WHERE key = ? LIMIT 1 FOR UPDATE", key)).any?
    end

    # Database wall clock as exact text (microseconds), read after the lock is held.
    def admission_clock
      connection.select_value("SELECT clock_timestamp()::text")
    end

    def read_window(key, clock)
      row = connection.select_rows(ApplicationRecord.sql(<<~SQL, clock, clock, key)).first
        SELECT CASE WHEN expires_at <= ?::timestamptz THEN 0 ELSE hits END,
               GREATEST(1, CEIL(EXTRACT(EPOCH FROM (expires_at - ?::timestamptz))))::int
        FROM rate_limits WHERE key = ? LIMIT 1
      SQL
      row&.map(&:to_i)
    end

    # Counts one admission at `clock`; an expired window restarts at 1.
    def bump_window(key, window_minutes, clock)
      minutes = Integer(window_minutes)
      expired = "rate_limits.expires_at <= #{connection.quote(clock)}::timestamptz"
      fresh = "#{connection.quote(clock)}::timestamptz + make_interval(mins => #{minutes})"
      connection.execute(ApplicationRecord.sql(<<~SQL, key))
        INSERT INTO rate_limits (key, hits, expires_at) VALUES (?, 1, #{fresh})
        ON CONFLICT (key) DO UPDATE SET
          hits = CASE WHEN #{expired} THEN 1 ELSE rate_limits.hits + 1 END,
          expires_at = CASE WHEN #{expired} THEN #{fresh} ELSE rate_limits.expires_at END,
          updated_at = now()
      SQL
    end

    # Bounded cleanup of windows expired at `clock` with the given key prefix.
    def delete_expired_windows(prefix, clock, batch = 500)
      connection.execute(ApplicationRecord.sql(<<~SQL, clock, prefix, batch))
        DELETE FROM rate_limits WHERE id IN (
          SELECT id FROM rate_limits WHERE expires_at <= ?::timestamptz AND starts_with(key, ?) LIMIT ?
        )
      SQL
    end
  end
end
