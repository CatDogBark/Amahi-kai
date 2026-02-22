// Shares plugin JS
//
// All interactions handled by Stimulus controllers:
//   - create_form_controller.js — new share form
//   - delete_controller.js — delete share
//   - toggle_controller.js — visibility, access, permissions checkboxes
//   - inline_edit_controller.js — path, extras, workgroup editing

function updatePoolCopies(shareId, copies) {
  var spinner = document.getElementById('pool-spinner-' + shareId);
  if (spinner) spinner.style.display = '';

  fetch('/shares/' + shareId + '/update_disk_pool_copies', {
    method: 'PUT',
    headers: Object.assign(csrfHeaders(), {'Content-Type': 'application/x-www-form-urlencoded'}),
    credentials: 'same-origin',
    body: 'copies=' + copies
  })
    .then(function(r) { return r.json(); })
    .then(function() { window.location.reload(); })
    .catch(function(err) {
      console.error('Pool copies update failed:', err);
      if (spinner) spinner.style.display = 'none';
    });
}

// When "All Users" is toggled, show/hide per-user section and writeable option
document.addEventListener("toggle:success", function(e) {
  var cb = e.target.querySelector('.share_everyone_checkbox');
  if (!cb) return;
  var container = cb.closest('.access');
  if (!container) return;
  var isEveryone = cb.checked;
  var everyoneOpts = container.querySelector('[data-access-show="everyone"]');
  var perUser = container.querySelector('[data-access-show="per-user"]');
  if (everyoneOpts) everyoneOpts.style.display = isEveryone ? '' : 'none';
  if (perUser) perUser.style.display = isEveryone ? 'none' : '';
});

// When per-user access is toggled, enable/disable the write checkbox
document.addEventListener("toggle:success", function(e) {
  var cb = e.target.querySelector('.share_access_checkbox');
  if (!cb) return;
  var row = cb.closest('tr');
  if (!row) return;
  var writeCb = row.querySelector('.share_write_checkbox');
  if (writeCb) writeCb.disabled = !cb.checked;
});

// When guest access is toggled, enable/disable guest writeable
document.addEventListener("toggle:success", function(e) {
  var cb = e.target.querySelector('.share_guest_access_checkbox');
  if (!cb) return;
  var row = cb.closest('tr');
  if (!row) return;
  var writeCb = row.querySelector('.share_guest_writeable_checkbox');
  if (writeCb) writeCb.disabled = !cb.checked;
});

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
