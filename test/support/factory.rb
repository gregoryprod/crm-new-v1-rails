# Synthetic records created by the tests themselves (no real personal data).
module Factory
  PASSWORD = "synthetic-password-1"

  def staff(role: "ADMIN", name: "Сотрудник #{SecureRandom.hex(3)}", active: true)
    @password_hash ||= Auth::Passwords.hash(PASSWORD)
    User.create!(email: "staff-#{SecureRandom.hex(4)}@example.test", name:, role:, password_hash: @password_hash, active:)
  end

  def lead_body(**overrides)
    {
      "last_name" => "Иванова", "first_name" => "Мария", "phone" => "8 (999) 123-45-67", "species" => "кошка",
      "consent_pd" => true, "consent_marketing" => false, "quiz_version" => "test-quiz-v1",
      "idempotency_key" => SecureRandom.uuid, "utm" => { "source" => "vk", "campaign" => "autumn" },
      "page_url" => "https://quiz.example.test/form?phone=79991234567#x"
    }.merge(overrides.transform_keys(&:to_s))
  end

  def doctor_with_service(duration: 30, price_cents: 150_000)
    doctor = Doctor.create!(name: "Врач #{SecureRandom.hex(2)}", specialty: "терапевт")
    service = DoctorService.create!(doctor_id: doctor.id, title: "Консультация", duration_minutes: duration,
                                    price_cents:, prepayment_percent: 0)
    [ doctor, service ]
  end

  def shift(doctor, day:, from: "09:00", to: "18:00")
    CalendarInterval.create!(doctor_id: doctor.id, kind: "shift",
                             start_at: Time.iso8601("#{day}T#{from}:00+03:00"), end_at: Time.iso8601("#{day}T#{to}:00+03:00"))
  end

  def client_with_patient
    client = Client.create!(last_name: "Петров", first_name: "Пётр", phone: "+79990001122", phone_raw: "+7 999 000-11-22", source: "MANUAL")
    [ client, Patient.create!(client_id: client.id, species: "собака", name: "Шарик") ]
  end

  def tomorrow = (Time.current.getlocal("+03:00").to_date + 1).iso8601
end
