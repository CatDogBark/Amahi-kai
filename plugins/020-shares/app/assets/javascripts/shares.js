// Shares plugin JS
//
// Share interactions are now handled by Stimulus controllers:
//   - create_form_controller.js — new share form
//   - delete_controller.js — delete share
//   - toggle_controller.js — visibility, access, permissions checkboxes
//   - inline_edit_controller.js — path, extras, workgroup editing
//
// Global open/close area and stretch-toggle handlers are in lib/application.js

$(function() {
  // Auto-fill path when name is entered
  $(document).on("blur", "#share_name", function() {
    var nameField = $(this);
    var pathField = $("#share_path");
    if (nameField.val() !== "" && pathField.length && pathField.val() === "") {
      pathField.val(pathField.data("pre") + nameField.val());
      pathField.focus();
    }
  });
});
