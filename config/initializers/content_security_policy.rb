# Content Security Policy
# https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Content-Security-Policy
#
# Start in report-only mode to catch violations without breaking functionality.
# Switch to enforcing mode once all violations are resolved.

Rails.application.config.content_security_policy do |policy|
  policy.default_src :self
  policy.font_src    :self, :data
  policy.img_src     :self, :data
  policy.object_src  :none
  policy.script_src  :self, :unsafe_inline  # needed for jquery_ujs inline handlers
  policy.style_src   :self, :unsafe_inline  # needed for inline styles in views
  policy.connect_src :self
  policy.frame_src   :none
  policy.base_uri    :self
  policy.form_action :self
end

# Report-only mode — logs violations but doesn't block them
# Remove this line to enforce the policy
Rails.application.config.content_security_policy_report_only = true
