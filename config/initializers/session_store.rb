# Be sure to restart your server when you modify this file.

AmahiKai::Application.config.session_store :cookie_store,
  key: '_amahi_kai_session',
  httponly: true,
  same_site: :lax,
  # The cookie lasts 7 days from the last request; UserSession enforces the same limit.
  expire_after: 7.days
  # secure: true  # Enable when serving over HTTPS
