# Optional local .env (development and tests only). Variables already set in the
# environment take precedence, like process.loadEnvFile in the previous Node scripts.
module EnvFile
  def self.load(path)
    return unless File.file?(path)

    File.foreach(path, encoding: "UTF-8") do |line|
      line = line.strip
      next if line.empty? || line.start_with?("#")

      key, value = line.split("=", 2)
      next if value.nil? || !key.match?(/\A[A-Z_][A-Z0-9_]*\z/)

      value = value.strip
      value = value[1..-2] if value.length >= 2 && value.start_with?('"', "'") && value[0] == value[-1]
      ENV[key] = value unless ENV.key?(key)
    end
  end
end
