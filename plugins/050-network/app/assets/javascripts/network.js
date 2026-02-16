// Network plugin JS
//
// Network interactions are now handled by Stimulus controllers:
//   - create_form_controller.js — new host/dns alias forms
//   - delete_controller.js — delete host/dns alias
//   - toggle_controller.js — DHCP server toggle, DNS provider select
//   - inline_edit_controller.js — lease time, gateway, DHCP range edits
//
// Only UI behaviors that don't involve AJAX remain here.

$(function() {
  // Stretch-toggle: expand/collapse entry detail panels
  $(document).on("click", ".stretchtoggle", function() {
    $(this).next(".settings-stretcher").slideToggle();
  });

  // Open/close new entry form areas
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

  // Live preview: update IP hint as user types address
  $(document).on('keyup', '#host_address, #dns_alias_address', function() {
    $('#net-message').text($(this).val());
  });

  // DNS provider: show/hide custom IPs area
  $(document).on('change', '#setting_dns', function() {
    if ($(this).val() === 'custom') {
      $('.dns-ips-area').show();
    } else {
      $('.dns-ips-area').hide();
    }
  });
});
