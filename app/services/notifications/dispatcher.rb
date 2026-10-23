module Notifications
  # Delivers due outbox events one by one until none are due (or the batch / stop limit).
  # Each event is claimed in its own short statement, so the lease covers exactly one send.
  # At-least-once: if the process dies after Telegram accepted the message but before SENT
  # is committed, the event is re-sent after the lease (the Bot API has no idempotency key).
  module Dispatcher
    Summary = Struct.new(:sent, :retried, :failed, :lease_lost, keyword_init: true)
    Attempt = TelegramChannel::Result
    HANDLED_EVENT_TYPES = %w[lead.created].freeze

    module_function

    def dispatch_due(channel:, app_origin:, max_events: 100, should_stop: -> { false })
      summary = Summary.new(sent: 0, retried: 0, failed: 0, lease_lost: 0)
      Outbox.fail_abandoned.each do |id|
        summary.failed += 1
        LogEvent.warn("notifications.abandoned_failed", event_id: id)
      end

      max_events.times do
        break if should_stop.call
        event = Outbox.claim_next(HANDLED_EVENT_TYPES)
        break unless event
        result = attempt(event, channel, app_origin)
        fields = { event_id: event.id, type: event.type, attempt: event.attempts, channel: channel.name }
        if result.ok
          if Outbox.mark_sent(event)
            summary.sent += 1
            LogEvent.info("notifications.sent", fields)
          else
            summary.lease_lost += 1
            LogEvent.warn("notifications.lease_lost", fields)
          end
          next
        end
        outcome = Outbox.mark_failed(event, error: result.error, retry_after_seconds: result.retry_after_seconds, permanent: result.permanent)
        case outcome
        when "retry" then summary.retried += 1
        when "failed" then summary.failed += 1
        else summary.lease_lost += 1
        end
        # The error text stays in the database (shown in the CRM); logs carry only the outcome.
        LogEvent.warn("notifications.#{outcome}", fields.merge(permanent: result.permanent == true))
      end
      summary
    end

    def attempt(event, channel, app_origin)
      return Attempt.failure("Неизвестный тип события", permanent: true) unless event.type == "lead.created"
      lead_id = event.payload.is_a?(Hash) ? event.payload["lead_id"] : nil
      return Attempt.failure("Некорректное событие: нет lead_id", permanent: true) unless CryptoHelpers.uuid?(lead_id)
      data = LeadMessage.find(lead_id)
      return Attempt.failure("Заявка не найдена", permanent: true) unless data
      channel.send_message(LeadMessage.build(data, app_origin))
    rescue StandardError => e
      # A channel must not raise; if it does, the message may hold request details.
      LogEvent.error("notifications.channel_threw", e, event_id: event.id)
      Attempt.failure("Внутренняя ошибка отправки")
    end
  end
end
