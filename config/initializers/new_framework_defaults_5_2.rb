# Be sure to restart your server when you modify this file.
#
# Rails 5.2 framework defaults — enabled for Rails 6 readiness.

# Make Active Record use stable #cache_key alongside new #cache_version method.
Rails.application.config.active_record.cache_versioning = true

# Use AES-256-GCM authenticated encryption for encrypted cookies.
Rails.application.config.action_dispatch.use_authenticated_cookie_encryption = true

# Use AES-256-GCM authenticated encryption as default cipher for encrypting messages.
Rails.application.config.active_support.use_authenticated_message_encryption = true

# Add default protection from forgery to ActionController::Base instead of in ApplicationController.
Rails.application.config.action_controller.default_protect_from_forgery = true

# Store boolean values in sqlite3 databases as 1 and 0 instead of 't' and 'f'.
Rails.application.config.active_record.sqlite3.represent_boolean_as_integer = true

# Use SHA-1 instead of MD5 to generate non-sensitive digests, such as the ETag header.
Rails.application.config.active_support.use_sha1_digests = true
