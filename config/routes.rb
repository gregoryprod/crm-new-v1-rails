Rails.application.routes.draw do
  # Liveness for kamal-proxy; /api/health also checks PostgreSQL.
  get "up" => "rails/health#show", as: :rails_health_check

  # --- JSON API (same paths and contracts as the previous Node app) ---------------------
  scope "api", module: "api" do
    get "health" => "health#show"

    post "auth/login" => "auth#login"
    post "auth/logout" => "auth#logout"
    get "auth/session" => "auth#session"
    get "users" => "users#index"

    # Public quiz intake (cross-origin from the clinic site).
    match "leads" => "leads#preflight", via: :options
    post "leads" => "leads#create"

    get "booking/catalog" => "booking#catalog"
    get "booking/slots" => "booking#slots"
    post "booking" => "booking#create"

    scope "crm", module: "crm" do
      get "leads" => "leads#index"
      get "leads/:id" => "leads#show"
      patch "leads/:id" => "leads#update"

      get "clients" => "clients#index"
      get "clients/:id" => "clients#show"
      post "clients/:id/patients" => "clients#create_patient"

      get "calendar" => "calendar#show"
      post "calendar" => "calendar#create"
      get "calendar/slots" => "calendar#slots"
      get "calendar/patients" => "calendar#patients"
      get "calendar/appointments/:id" => "calendar#appointment"

      get "full" => "full#show"
      match "full" => "full#write", via: %i[post put]
      get "full-assets" => "full#assets"
    end
  end

  # --- Staff pages ----------------------------------------------------------------------
  root "pages#root"
  get "login" => "pages#login"
  post "login" => "sessions#create"
  get "crm" => "pages#crm"
  get "crm/full" => "pages#full"
  get "crm/analytics" => "pages#analytics"

  get "crm/leads" => "leads#index"
  get "crm/leads/:id" => "leads#show"
  patch "crm/leads/:id" => "leads#update"

  get "crm/clients" => "clients#index"
  get "crm/clients/:id" => "clients#show"
  post "crm/clients/:id/patients" => "clients#create_patient"

  get "crm/calendar" => "calendar#show"
  post "crm/calendar" => "calendar#command"

  get "quiz" => "quiz#show"
  post "quiz" => "quiz#create"
  post "quiz/booking" => "quiz#book"
end
