// Shares plugin JS
//
// All interactions handled by Stimulus controllers:
//   - create_form_controller.js — new share form
//   - delete_controller.js — delete share
//   - toggle_controller.js — visibility, access, permissions checkboxes
//   - inline_edit_controller.js — path, extras, workgroup editing

document.addEventListener("DOMContentLoaded", function() {
  // Auto-fill path when name is entered
  document.addEventListener("blur", function(event) {
    if (event.target.id === "share_name") {
      var pathField = document.getElementById("share_path");
      if (event.target.value !== "" && pathField && pathField.value === "") {
        pathField.value = (pathField.dataset.pre || "") + event.target.value;
        pathField.focus();
      }
    }
  }, true);
});
