# Staff session cookie: HTTPS origins get `Secure` and the `__Host-` prefix; plain HTTP is
# allowed by env validation only for loopback development.
module SessionCookie
  def self.cookie_name
    secure? ? "__Host-vpc_session" : "vpc_session"
  end

  def self.secure?
    AppEnv.server.app_origin.start_with?("https:")
  end

  def self.cookie_options(value, max_age)
    { value:, httponly: true, secure: secure?, same_site: :lax, path: "/", expires: max_age.zero? ? Time.at(0) : max_age.seconds.from_now }
  end
end
