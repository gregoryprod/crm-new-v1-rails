# Files in public/full-crm, public/fonts and the icon have no fingerprint in their names, so a
# long cache would keep stale workspace code and styles after a deploy. They are revalidated
# on every load (Last-Modified → 304); fingerprinted /assets keep the long cache.
class UnversionedStaticCacheControl
  PREFIXES = %w[/full-crm/ /fonts/].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    path = env["PATH_INFO"].to_s
    headers["cache-control"] = "public, no-cache" if path.start_with?(*PREFIXES) || path == "/icon.svg"
    [ status, headers, body ]
  end
end

Rails.application.config.middleware.insert_before ActionDispatch::Static, UnversionedStaticCacheControl
