# Content Security Policy, enforced: scripts only from Amahi-kai itself (no inline scripts
# or handlers: every page's JavaScript is a file, and buttons say what they do in their markup,
# lib/dispatch.js), so a script smuggled into a page can't act as the person signed in.
# Styles still allow inline ones (the views have many style attributes); that's the next step.
# Pictures only from Amahi-kai itself: apps' logos are served by the NAS (AppLogosController,
# since 1.8.5), so no page loads one from another site. The file browser frames a PDF from
# Amahi-kai itself; files served from shares set their own sandbox policy
# (FileBrowserController#raw).
Rails.application.config.content_security_policy do |policy|
  policy.default_src :self
  policy.font_src    :self, :data
  policy.img_src     :self, :data
  policy.media_src   :self
  policy.object_src  :none
  policy.script_src  :self
  policy.style_src   :self, :unsafe_inline
  policy.connect_src :self
  policy.frame_src   :self
  policy.base_uri    :self
  policy.form_action :self
end
