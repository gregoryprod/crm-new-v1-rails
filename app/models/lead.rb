class Lead < ApplicationRecord
  STATUSES = %w[NEW IN_PROGRESS DONE SPAM].freeze
  STATUS_LABELS = { "NEW" => "Новая", "IN_PROGRESS" => "В работе", "DONE" => "Завершена", "SPAM" => "Спам" }.freeze

  belongs_to :client
  belongs_to :patient
end
