module Api
  # User management is OWNER-only; ADMIN receives 403 from the server guard.
  class UsersController < ApiController
    def index
      require_staff("OWNER")
      render_json({ "users" => User.order(:created_at).map(&:public_attributes) })
    end
  end
end
