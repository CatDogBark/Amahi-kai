# Secret key base configuration
#
# Rails 7.2 removed config/secrets.yml support.
# For production: set SECRET_KEY_BASE environment variable
# For dev/test: use deterministic keys below (safe since they're not used in production)

Rails.application.configure do
  config.secret_key_base = if ENV['SECRET_KEY_BASE'].present?
    ENV['SECRET_KEY_BASE']
  elsif Rails.env.production?
    raise "SECRET_KEY_BASE environment variable must be set in production!"
  else
    # Deterministic keys for dev/test (not secret, not used in production)
    Digest::SHA512.hexdigest("amahi-kai-#{Rails.env}-secret-key-base")
  end
end
