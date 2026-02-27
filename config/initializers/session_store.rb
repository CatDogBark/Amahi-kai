# Be sure to restart your server when you modify this file.

AmahiKai::Application.config.session_store :cookie_store,
  key: '_amahi_kai_session',
  httponly: true,
  same_site: :lax
  # secure: true  # Enable when serving over HTTPS
