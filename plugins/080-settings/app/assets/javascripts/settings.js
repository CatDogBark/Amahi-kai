// Settings plugin JS
//
// Server actions and checkbox toggles are now handled by Stimulus controllers:
//   - server_action_controller.js — refresh/start/stop/restart + checkbox toggles
//   - toggle_controller.js — advanced settings, guest dashboard toggles
//   - locale_controller.js — language select → reload page
//
// The jQuery handlers below are kept temporarily for backward compatibility
// during the Turbo migration. They will be removed once all plugins are converted.

// Stretch-toggle behavior for server rows (expand/collapse detail panel)
$(function() {
  $(document).on("click", ".stretchtoggle", function() {
    $(this).next(".settings-stretcher").slideToggle();
  });
});
