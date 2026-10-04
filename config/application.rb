require_relative 'boot'

require 'rails/all'

Bundler.require(*Rails.groups)
Bundler.require(:default, :assets, Rails.env)

module AmahiKai
  class Application < Rails::Application
    config.load_defaults 8.1
    config.autoload_paths += %W(#{config.root}/lib)
    config.amahi_plugins = []
  end
end
