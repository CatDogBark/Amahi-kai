# Be sure to restart your server when you modify this file.
#
# This file contains migration options to ease your Rails 5.0 upgrade.
# All values updated to Rails 5.2 recommended defaults.

# Enable per-form CSRF tokens.
Rails.application.config.action_controller.per_form_csrf_tokens = true

# Enable origin-checking CSRF mitigation.
Rails.application.config.action_controller.forgery_protection_origin_check = true

# Make Ruby 2.4+ preserve the timezone of the receiver when calling `to_time`.
ActiveSupport.to_time_preserves_timezone = true

# Require `belongs_to` associations by default.
# NOTE: Disabled for now — enabling this requires auditing all belongs_to
# associations for optional: true where nil foreign keys are expected.
Rails.application.config.active_record.belongs_to_required_by_default = false
