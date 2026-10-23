# Delivery protocol of the outbox table. One attempt = claim → external send → finish.
# `attempts` is incremented by the claim and doubles as a fencing token: a worker may finish
# only the attempt it claimed. The claim moves `next_attempt_at` forward by the lease, so a
# crashed worker's event becomes due again after the lease. All times come from the
# database clock, so several worker processes agree on them.
module Outbox
  # Initial attempt plus retries after 1, 5 and 15 minutes; then FAILED.
  RETRY_DELAYS_SECONDS = [ 60, 300, 900 ].freeze
  MAX_ATTEMPTS = RETRY_DELAYS_SECONDS.length + 1
  # Must exceed the longest send (TELEGRAM_TIMEOUT_SECONDS ≤ 60).
  LEASE_SECONDS = 120
  MAX_RETRY_AFTER_SECONDS = 3_600

  Claimed = Data.define(:id, :type, :payload, :attempts)

  module_function

  def connection
    ActiveRecord::Base.connection
  end

  # Atomically takes the oldest due PENDING event of the given types (SKIP LOCKED).
  def claim_next(types)
    return nil if types.empty?
    row = connection.select_all(ApplicationRecord.sql(<<~SQL, LEASE_SECONDS, MAX_ATTEMPTS, types)).cast_values.first
      UPDATE outbox
      SET attempts = attempts + 1,
          next_attempt_at = now() + make_interval(secs => ?),
          updated_at = now()
      WHERE id = (
        SELECT id FROM outbox
        WHERE status = 'PENDING' AND next_attempt_at <= now() AND attempts < ? AND type IN (?)
        ORDER BY next_attempt_at, created_at
        LIMIT 1
        FOR UPDATE SKIP LOCKED
      )
      RETURNING id, type, payload, attempts
    SQL
    row && Claimed.new(id: row[0], type: row[1], payload: row[2].is_a?(String) ? JSON.parse(row[2]) : row[2], attempts: row[3])
  end

  # Events whose final attempt never finished (worker crashed) and whose lease expired.
  def fail_abandoned
    connection.select_values(ApplicationRecord.sql(<<~SQL, MAX_ATTEMPTS))
      UPDATE outbox
      SET status = 'FAILED',
          last_error = 'Последняя попытка прервана остановкой worker; попытки исчерпаны',
          updated_at = now()
      WHERE status = 'PENDING' AND attempts >= ? AND next_attempt_at <= now()
      RETURNING id
    SQL
  end

  # False when the lease was lost (another worker re-claimed the event after expiry).
  def mark_sent(event)
    connection.select_values(ApplicationRecord.sql(<<~SQL, event.id, event.attempts)).any?
      UPDATE outbox SET status = 'SENT', last_error = NULL, updated_at = now()
      WHERE id = ? AND attempts = ? AND status = 'PENDING' RETURNING id
    SQL
  end

  # Schedules the next retry (never sooner than the provider's hint) or marks FAILED when
  # attempts are exhausted or the failure is permanent. `error` must already be secret-free.
  def mark_failed(event, error:, retry_after_seconds: nil, permanent: false)
    exhausted = permanent || event.attempts >= MAX_ATTEMPTS
    scheduled = RETRY_DELAYS_SECONDS[[ event.attempts, RETRY_DELAYS_SECONDS.length ].min - 1] || 0
    delay = [ scheduled, [ retry_after_seconds || 0, MAX_RETRY_AFTER_SECONDS ].min ].max
    set = exhausted ? "status = 'FAILED', last_error = ?, updated_at = now()" : "last_error = ?, next_attempt_at = now() + make_interval(secs => #{Integer(delay)}), updated_at = now()"
    rows = connection.select_values(ApplicationRecord.sql(<<~SQL, error, event.id, event.attempts))
      UPDATE outbox SET #{set} WHERE id = ? AND attempts = ? AND status = 'PENDING' RETURNING id
    SQL
    return "lease_lost" if rows.empty?
    exhausted ? "failed" : "retry"
  end

  # Delivery state of the lead's `lead.created` notification, if one was enqueued.
  def lead_delivery(lead_id)
    row = OutboxEvent.where(type: "lead.created").where("payload ->> 'lead_id' = ?", lead_id)
      .order(created_at: :desc).pick(:status, :attempts, :last_error, :next_attempt_at, :updated_at)
    return nil unless row
    %w[status attempts lastError nextAttemptAt updatedAt].zip(row).to_h.merge("maxAttempts" => MAX_ATTEMPTS)
  end
end
