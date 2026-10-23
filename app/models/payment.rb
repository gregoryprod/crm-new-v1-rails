# Confirmed service receipts, separate from quoted appointment prices and deposits.
class Payment < ApplicationRecord
  METHOD_LABELS = { "cash" => "Наличные", "card" => "Карта", "transfer" => "Перевод" }.freeze
end
