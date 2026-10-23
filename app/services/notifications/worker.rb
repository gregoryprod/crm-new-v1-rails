module Notifications
  # Long-running notification worker next to the web app (`bin/rails notifications:work`).
  # Polls the outbox every WORKER_POLL_SECONDS; several instances may run at once (claims use
  # SKIP LOCKED and a lease). SIGINT/SIGTERM finish the current send and exit cleanly.
  # `once: true` drains due events a single time and exits.
  module Worker
    BATCH = 100

    module_function

    def run(once: false)
      begin
        app_origin = AppEnv.server.app_origin
        env = AppEnv.parse_notifications(ENV)
      rescue AppEnv::Error => e
        warn e.message
        return 1
      end
      channel = TelegramChannel.new(bot_token: env.telegram_bot_token, chat_id: env.telegram_admin_chat_id,
                                    api_base_url: env.telegram_api_base_url, timeout_seconds: env.telegram_timeout_seconds)
      stop = false
      previous = %w[INT TERM].to_h { |signal| [ signal, trap(signal) { stop = true } ] }
      LogEvent.info("notifications.worker_started", channel: channel.name, poll_seconds: env.worker_poll_seconds, once:)
      until stop
        busy = false
        begin
          summary = Dispatcher.dispatch_due(channel:, app_origin:, max_events: BATCH, should_stop: -> { stop })
          busy = summary.sent + summary.retried + summary.failed + summary.lease_lost >= BATCH
        rescue StandardError => e
          # Database unavailable etc.: claimed events come back after their lease.
          LogEvent.error("notifications.dispatch_failed", e)
        end
        break if once
        unless busy
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + env.worker_poll_seconds
          sleep 0.2 while !stop && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        end
      end
      0
    ensure
      previous&.each { |signal, handler| trap(signal, handler || "DEFAULT") }
      LogEvent.info("notifications.worker_stopped") if env
    end
  end
end
