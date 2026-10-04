require_relative 'boot'

require 'rails/all'

Bundler.require(*Rails.groups)
Bundler.require(:default, :assets, Rails.env)

module AmahiKai
  class Application < Rails::Application
    config.load_defaults 8.1
    # English only: the original Amahi's translations were dropped (newer screens were never
    # translated, so other languages showed a mix).
    config.i18n.available_locales = [:en]
    config.i18n.default_locale = :en
    config.autoload_paths += %W(#{config.root}/lib)
  end
end
