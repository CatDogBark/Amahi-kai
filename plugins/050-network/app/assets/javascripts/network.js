// Network plugin JS
//
// Network interactions are now handled by Stimulus controllers:
//   - create_form_controller.js — new host/dns alias forms
//   - delete_controller.js — delete host/dns alias
//   - toggle_controller.js — DHCP server toggle, DNS provider select
//   - inline_edit_controller.js — lease time, gateway, DHCP range edits
//
// Global open/close area and stretch-toggle handlers are in lib/application.js

$(function() {
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
