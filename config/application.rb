require_relative 'boot'

require 'rails/all'


# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# We want our assets lazily compiled in production
Bundler.require(:default, :assets, Rails.env)

module AmahiHDA
  class Application < Rails::Application

    config.load_defaults 8.0

    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    # Custom directories with classes and modules you want to be autoloadable.
    config.autoload_paths += %W(#{config.root}/lib)

    # Only load the plugins named here, in the order given (default is alphabetical).
    # :all can be used as a placeholder for all plugins not explicitly named.
    # config.plugins = [ :exception_notification, :ssl_requirement, :all ]

    # Activate observers that should always be running.
    # config.active_record.observers = :cacher, :garbage_collector, :forum_observer

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    # config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}').to_s]
    # config.i18n.default_locale = :en
    # config.i18n.enforce_available_locales = true

    # initialize tabs app variable

    # in case we need to debug assets
    # config.assets.debug = true

  end
end

############################################
# load all Amahi platform plugins installed
############################################
module AmahiHDA
  class Application < Rails::Application
    # Legacy plugins have been consolidated into the main app.
    # Keep empty config for backward compatibility.
    config.amahi_plugins = []
  end
end
