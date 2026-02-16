// Shares plugin JS
//
// Share interactions are now handled by Stimulus controllers:
//   - create_form_controller.js — new share form
//   - delete_controller.js — delete share
//   - toggle_controller.js — visibility, access, permissions checkboxes
//   - inline_edit_controller.js — path, extras, workgroup editing
//
// Only UI behaviors that don't involve AJAX remain here.

$(function() {
  // Stretch-toggle: expand/collapse share detail panels
  $(document).on("click", ".stretchtoggle", function() {
    $(this).next(".settings-stretcher").slideToggle();
  });

  // Open/close new share form area
  $(document).on("click", ".open-area", function(event) {
    event.preventDefault();
    var related = $(this).data("related");
    $(related).slideToggle();
  });

  $(document).on("click", ".close-area", function(event) {
    event.preventDefault();
    var related = $(this).data("related");
    $(related).slideUp();
  });

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
