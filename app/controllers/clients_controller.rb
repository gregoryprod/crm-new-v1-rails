class ClientsController < ApplicationController
  def index
    require_page_role
    return if performed?
    @q = request.query_parameters["q"].to_s
    query = Clients::Directory.parse_query(request.query_parameters) || { "q" => "", "page" => 1 }
    @data = begin
      Clients::Directory.list(query)
    rescue StandardError => e
      LogEvent.error("clients.page_failed", e)
      nil
    end
  end

  def show
    require_page_role
    return if performed?
    @details = Clients::Directory.details(params[:id])
    return not_found! unless @details
    @payments = begin
      Payments::Listing.list("clientId" => params[:id])
    rescue StandardError => e
      LogEvent.error("payments.client_failed", e)
      nil
    end
  end

  def create_patient
    require_page_role
    return if performed?
    input = Clients::Directory.parse_patient(
      "operationId" => params[:operation_id].to_s, "name" => params[:name].to_s,
      "species" => params[:species].to_s, "confirmed" => params[:confirmed] == "1"
    )
    back = "/crm/clients/#{params[:id]}"
    return redirect_to(back, alert: "Не удалось сохранить. Проверь поля и доступ.", status: :see_other) unless input
    kind, = Clients::Directory.create_confirmed_patient(current_user.id, params[:id], input)
    return not_found! if kind == :not_found
    message = kind == :saved ? { notice: "Питомец сохранён. Теперь его можно выбрать в расписании." } : { alert: "Не удалось сохранить. Проверь поля и доступ." }
    redirect_to back, status: :see_other, **message
  end
end
