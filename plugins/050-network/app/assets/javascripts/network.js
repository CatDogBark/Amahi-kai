// Network plugin JS
//
// All interactions handled by Stimulus controllers:
//   - create_form_controller.js — new host/dns alias forms
//   - delete_controller.js — delete host/dns alias
//   - toggle_controller.js — DHCP server toggle, DNS provider select
//   - inline_edit_controller.js — lease time, gateway, DHCP range edits

document.addEventListener("DOMContentLoaded", function() {
  // Live preview: update IP hint as user types address
  document.addEventListener("keyup", function(event) {
    if (event.target.id === "host_address" || event.target.id === "dns_alias_address") {
      var hint = document.getElementById("net-message");
      if (hint) hint.textContent = event.target.value;
    }
  }, true);

  // DNS provider: show/hide custom IPs area
  document.addEventListener("change", function(event) {
    if (event.target.id === "setting_dns") {
      var area = document.querySelector(".dns-ips-area");
      if (area) {
        area.style.display = event.target.value === "custom" ? "" : "none";
      }
    }
  }, true);
});
