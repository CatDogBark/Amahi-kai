// Users plugin JS
//
// User interactions are now handled by Stimulus controllers:
//   - user_controller.js — delete, toggle admin, edit name, password, pin
//   - create_form_controller.js — new user form
//
// Only UI behaviors that don't involve AJAX remain here.

$(function() {
  // Stretch-toggle: expand/collapse user detail panels
  $(document).on("click", ".stretchtoggle", function() {
    $(this).next(".settings-stretcher").slideToggle();
  });

  // Open/close new user form area
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
});
