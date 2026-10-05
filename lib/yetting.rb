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

    def method_missing(name, *args)
      key = name.to_s
      if settings.key?(key)
        settings[key]
      else
        super
      end
    end

    def respond_to_missing?(name, include_private = false)
      settings.key?(name.to_s) || super
    end

    def reload!
      @settings = nil
      settings
    end
  end
end
