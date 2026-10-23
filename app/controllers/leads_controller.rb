class LeadsController < ApplicationController
  FILTER_LABELS = { "status" => "статус", "from" => "дата с", "to" => "дата по", "source" => "источник", "q" => "поиск", "page" => "страница" }.freeze

  helper_method :page_href

  def index
    require_page_role
    return if performed?
    @query, @invalid = Leads::Staff.parse_query(request.query_parameters)
    @result = Leads::Staff.list_page(@query)
    @filtered = [ @query.status, @query.from, @query.to, @query.source, @query.q ].any?
  end

  def show
    require_page_role
    return if performed?
    @lead = Leads::Staff.card(params[:id])
    return not_found! unless @lead
    @delivery = Notifications::DeliveryView.describe(@lead["delivery"], @lead["honeypot"])
  end

  def update
    require_page_role
    return if performed?
    body = {
      "expectedVersion" => Integer(params[:expected_version].to_s, 10, exception: false),
      "status" => params[:status].to_s,
      "assigned_to" => params[:assigned_to].presence,
      "comment" => params[:comment].to_s
    }
    data, fields = Leads::Staff.parse_update(body)
    result = data ? Leads::Staff.update(current_user.id, params[:id], data) : { kind: "invalid", fields: }
    return not_found! if result[:kind] == "not_found"
    if %w[updated unchanged].include?(result[:kind])
      return redirect_to("/crm/leads/#{params[:id]}", notice: result[:kind] == "updated" ? "Изменения сохранены." : "Изменений нет.", status: :see_other)
    end
    @lead = Leads::Staff.card(params[:id])
    return not_found! unless @lead
    @delivery = Notifications::DeliveryView.describe(@lead["delivery"], @lead["honeypot"])
    @draft = { "status" => body["status"], "assigned_to" => body["assigned_to"], "comment" => body["comment"] }
    if result[:kind] == "stale"
      @conflict = @lead.slice("version", "status", "assignedTo", "comment")
      @update_message = "Заявку уже изменили. Черновик сохранён; сверь актуальные данные ниже и отправь его повторно."
    else
      labels = { "status" => "статус", "assigned_to" => "ответственный", "comment" => "комментарий", "body" => "запрос" }
      names = result[:fields].map { |f| labels.fetch(f, f) }.join(", ")
      @update_message = "Проверьте поля#{names.empty? ? '' : ": #{names}"}."
    end
    render :show, status: :unprocessable_content
  end

  private

  def page_href(query, page)
    params = %w[status from to source q].filter_map { |key| (value = query[key]) && [ key, value ] }
    params << [ "page", page.to_s ] if page > 1
    params.empty? ? "/crm/leads" : "/crm/leads?#{URI.encode_www_form(params)}"
  end
end
