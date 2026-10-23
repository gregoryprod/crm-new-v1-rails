module Notifications
  # Staff-facing state of the administrators' notification for a lead card.
  module DeliveryView
    View = Data.define(:label, :tone, :next_attempt_at, :finished_at, :attempts_text, :error)

    module_function

    def describe(delivery, lead_is_spam)
      empty = { next_attempt_at: nil, finished_at: nil, attempts_text: nil, error: nil }
      unless delivery
        label = lead_is_spam ? "Не отправляется: заявка помечена как спам при приёме" : "Уведомление для этой заявки не создавалось"
        return View.new(**empty, tone: "none", label:)
      end
      attempts_text = "#{delivery['attempts']} из #{delivery['maxAttempts']}"
      case delivery["status"]
      when "SENT"
        View.new(**empty, tone: "ok", label: "Доставлено в Telegram", finished_at: delivery["updatedAt"], attempts_text:)
      when "FAILED"
        View.new(**empty, tone: "failed", label: "Не доставлено — обработайте заявку без уведомления",
                          finished_at: delivery["updatedAt"], attempts_text:, error: delivery["lastError"])
      else
        return View.new(**empty, tone: "pending", label: "Ожидает отправки") if delivery["attempts"].zero?
        return View.new(**empty, tone: "pending", label: "Отправляется", attempts_text:) unless delivery["lastError"]
        View.new(**empty, tone: "pending", label: "Ошибка доставки, будет повтор", next_attempt_at: delivery["nextAttemptAt"],
                          attempts_text:, error: delivery["lastError"])
      end
    end
  end
end
