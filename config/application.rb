require_relative 'boot'

# Only the parts of Rails Amahi-kai uses (no mail, file attachments, rich text, inbound email
# or websockets): less to load, and less memory on the NAS.
require 'rails'
require 'active_model/railtie'
require 'active_job/railtie'
require 'active_record/railtie'
require 'action_controller/railtie'
require 'action_view/railtie'
require 'sprockets/railtie'

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
