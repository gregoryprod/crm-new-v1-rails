class PagesController < ApplicationController
  def root
    redirect_to "/crm", status: :see_other
  end

  def login
    response.headers["Cache-Control"] = "no-store"
    redirect_to("/crm", status: :see_other) if page_session
  end

  def crm
    require_page_role
    redirect_to "/crm/full", status: :see_other unless performed?
  end

  def full
    require_page_role
  end

  def analytics
    require_page_role
    return if performed?
    query = request.query_parameters.reject { |_, v| v.nil? || v == "" }
    @filter = Payments::Listing.parse(query.slice("from", "to", "doctorId"))
    return render("pages/analytics_invalid") unless @filter
    @rows = Payments::Listing.list(@filter)
    @doctors = Doctor.order(:name).pluck(:id, :name)
  end
end
