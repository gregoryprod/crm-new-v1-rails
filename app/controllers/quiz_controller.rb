# Built-in quiz: pet → contacts → lead (same intake as POST /api/leads) → time slot →
# booking (same service as POST /api/booking). The lead id and bearer booking receipt live
# only in the encrypted Rails session cookie, never in URLs.
class QuizController < ApplicationController
  QUIZ_VERSION = "main-quiz-v1"
  SPECIES = [ "Кошка", "Собака", "Другой питомец" ].freeze
  LEAD_ERRORS = {
    "invalid_request" => "Проверь имя, фамилию и телефон.",
    "too_many_requests" => "Слишком много попыток. Подожди немного и отправь заявку ещё раз.",
    "default" => "Не удалось отправить заявку. Проверь соединение и попробуй ещё раз."
  }.freeze

  def show
    return restart if params[:restart] == "1"
    @quiz = session[:quiz] || {}
    if @quiz["lead_id"]
      prepare_booking
    else
      @step = params[:step] == "contact" && SPECIES.include?(params[:species]) ? "contact" : "pet"
      @species = params[:species]
      @idempotency_key = SecureRandom.uuid
    end
  end

  def create
    @species = params[:species].to_s
    @idempotency_key = params[:idempotency_key].to_s
    body = {
      "last_name" => params[:last_name].to_s.strip, "first_name" => params[:first_name].to_s.strip,
      "phone" => params[:phone].to_s.strip, "species" => @species, "consent_pd" => params[:consent_pd] == "1",
      "consent_marketing" => params[:consent_marketing] == "1", "quiz_version" => QUIZ_VERSION,
      "idempotency_key" => @idempotency_key, "page_url" => request.url, "website" => params[:website].to_s
    }
    parsed = Leads::Payload.parse(body)
    return contact_error("invalid_request") unless parsed.ok
    result = Leads::Intake.submit(parsed.lead, ip: client_ip, user_agent: request.user_agent)
    case result.kind
    when "created", "replayed"
      session[:quiz] = { "lead_id" => result.lead_id, "booking_token" => Booking::Receipt.issue(result.lead_id) }
      redirect_to "/quiz", status: :see_other
    when "rate_limited" then contact_error("too_many_requests")
    else
      @idempotency_key = SecureRandom.uuid
      contact_error("default")
    end
  end

  def book
    quiz = session[:quiz] || {}
    return redirect_to("/quiz", status: :see_other) unless quiz["lead_id"] && quiz["booking_token"]
    command = Booking::Service.parse_command(
      "operationId" => params[:operation_id].to_s, "leadId" => quiz["lead_id"], "bookingToken" => quiz["booking_token"],
      "serviceId" => params[:service].to_s, "start" => params[:start].to_s
    )
    return booking_error("Выбери услугу и время приёма.") unless command
    result = Booking::Service.book(command)
    session[:quiz] = quiz.merge("booking" => result["booking"])
    redirect_to "/quiz", status: :see_other
  rescue Calendar::Error, ActiveRecord::StatementInvalid => e
    raise e if e.is_a?(ActiveRecord::StatementInvalid) && !%w[23P01 23505].include?(LogEvent.sqlstate(e))
    booking_error("Это время уже недоступно. Обнови расписание и выбери другой слот.")
  rescue Booking::Error => e
    booking_error(e.status == 429 ? "Слишком много попыток. Подожди немного и попробуй ещё раз." : "Не удалось записать на приём. Отправь заявку ещё раз.")
  end

  private

  def failure_event = "quiz.failed"

  def restart
    session.delete(:quiz)
    redirect_to "/quiz", status: :see_other
  end

  def contact_error(code)
    @step = "contact"
    @lead_error = LEAD_ERRORS.fetch(code)
    @quiz = {}
    render :show, status: :unprocessable_content
  end

  def booking_error(message)
    flash[:quiz_error] = message
    redirect_to "/quiz?#{URI.encode_www_form(params.permit(:doctor, :service, :day).to_h)}", status: :see_other
  end

  def prepare_booking
    @booking = @quiz["booking"]
    return if @booking || !@quiz["booking_token"]
    Booking::Service.admit_public_read
    @catalog = Booking::Service.catalog
    @doctor_id = @catalog["doctors"].find { |d| d["id"] == params[:doctor] }&.dig("id")
    @services = @catalog["services"].select { |s| s["doctorId"] == @doctor_id }
    @service = @services.find { |s| s["id"] == params[:service] }
    @day = Calendar::Slots.valid_day?(params[:day]) ? params[:day] : Calendar::Slots.moscow_day(Time.current)
    @slots = Calendar::Service.slots(day: @day, service_id: @service["id"])["slots"] if @service
    @operation_id = SecureRandom.uuid
  rescue Booking::Error
    @catalog_error = "Не удалось загрузить специалистов и услуги."
  end
end
