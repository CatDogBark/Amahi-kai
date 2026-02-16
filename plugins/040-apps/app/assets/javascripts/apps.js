// Apps plugin JS
//
// App interactions are now handled by Stimulus controllers:
//   - toggle_controller.js — dashboard visibility toggle
//
// Install/uninstall functionality is currently stubbed (AmahiApi offline).
// When re-enabled, progress_controller.js can handle polling.
//
// Only UI behaviors remain here.

$(function() {
  // Stretch-toggle: expand/collapse app detail panels
  $(document).on("click", ".stretchtoggle", function() {
    $(this).next(".settings-stretcher").slideToggle();
  });
});
