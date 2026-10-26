# Be sure to restart your server when you modify this file.

# The cookie ends with the browser unless the sign-in ticked Remember me: then it lasts
# UserSession::IDLE_TIMEOUT from the last request (ApplicationController#session_cookie_options,
# which also marks it Secure over the Cloudflare Tunnel). UserSession enforces the same limits.
AmahiKai::Application.config.session_store :cookie_store,
  key: '_amahi_kai_session',
  httponly: true,
  same_site: :lax
