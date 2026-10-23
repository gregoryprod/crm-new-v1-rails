module Notifications
  module LeadMessage
    module_function

    # Current lead data at send time: the outbox stores only the pointer.
    def find(lead_id)
      row = Lead.joins(:client, :patient).where(id: lead_id)
        .pick("leads.id", "clients.last_name", "clients.first_name", "clients.phone", "patients.species", "leads.utm")
      return nil unless row
      utm = row[5].is_a?(String) ? JSON.parse(row[5]) : row[5]
      source = utm.is_a?(Hash) ? utm["source"] : nil
      { id: row[0], last_name: row[1], first_name: row[2], phone: row[3], species: row[4],
        utm_source: source.is_a?(String) && source != "" ? source : nil }
    end

    # «Новая заявка: Фамилия Имя, телефон, вид питомца, источник, ссылка на карточку».
    def build(lead, app_origin)
      source = lead[:utm_source] ? "квиз, utm_source: #{lead[:utm_source]}" : "квиз"
      [
        "Новая заявка",
        "#{lead[:last_name]} #{lead[:first_name]}",
        "Телефон: #{lead[:phone] || 'не указан'}",
        "Питомец: #{lead[:species]}",
        "Источник: #{source}",
        "Карточка: #{app_origin}/crm/leads/#{lead[:id]}"
      ].join("\n")
    end
  end
end
