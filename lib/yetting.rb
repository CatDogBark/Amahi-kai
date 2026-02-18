# Custom replacement for the abandoned yettings gem.
# Loads config/yetting.yml and provides method-style access to settings.
class Yetting
  class << self
    def settings
      @settings ||= begin
        config_path = if defined?(Rails)
          Rails.root.join('config', 'yetting.yml')
        else
          File.expand_path('../../config/yetting.yml', __FILE__)
        end
        yaml = YAML.safe_load(File.read(config_path), permitted_classes: [Symbol], aliases: true)
        env = defined?(Rails) ? Rails.env.to_s : (ENV['RAILS_ENV'] || 'development')
        (yaml[env] || yaml['defaults'] || {}).freeze
      end
    end

    # Environment variable overrides for specific settings.
    # AMAHI_DUMMY_MODE=1 forces dummy mode on (useful for dev/staging).
    # AMAHI_DUMMY_MODE=0 forces dummy mode off (useful for production override).
    ENV_OVERRIDES = {
      'dummy_mode' => 'AMAHI_DUMMY_MODE'
    }.freeze

    def method_missing(name, *args)
      key = name.to_s

      # Check for env var override first
      if ENV_OVERRIDES.key?(key) && ENV.key?(ENV_OVERRIDES[key])
        return %w[1 true yes].include?(ENV[ENV_OVERRIDES[key]].to_s.downcase)
      end

      if settings.key?(key)
        settings[key]
      else
        super
      end
    end

    def respond_to_missing?(name, include_private = false)
      ENV_OVERRIDES.key?(name.to_s) || settings.key?(name.to_s) || super
    end

    def reload!
      @settings = nil
      settings
    end
  end
end
