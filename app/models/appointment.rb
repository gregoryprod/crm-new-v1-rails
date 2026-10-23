class Appointment < ApplicationRecord
  ATTENDANCE_LABELS = {
    "scheduled" => "Запланирован", "confirmed" => "Подтверждён", "arrived" => "Клиент пришёл",
    "completed" => "Завершён", "no_show" => "Неявка"
  }.freeze

  belongs_to :doctor
  belongs_to :client
  belongs_to :patient
end
