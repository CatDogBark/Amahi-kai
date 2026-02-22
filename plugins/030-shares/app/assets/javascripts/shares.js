// Shares plugin JS
//
// All interactions handled by Stimulus controllers:
//   - create_form_controller.js — new share form
//   - delete_controller.js — delete share
//   - toggle_controller.js — visibility, access, permissions checkboxes
//   - inline_edit_controller.js — path, extras, workgroup editing

function updatePoolCopies(shareId, copies) {
  var spinner = document.getElementById('pool-spinner-' + shareId);
  var container = document.getElementById('pool-controls-' + shareId);
  if (spinner) spinner.style.display = '';

  fetch('/shares/' + shareId + '/update_disk_pool_copies', {
    method: 'PUT',
    headers: Object.assign(csrfHeaders(), {'Content-Type': 'application/x-www-form-urlencoded'}),
    credentials: 'same-origin',
    body: 'copies=' + copies
  })
    .then(function(r) { return r.json(); })
    .then(function(data) {
      var c = data.disk_pool_copies;
      // Update label
      var label = document.getElementById('pool-copies-' + shareId);
      if (label) label.textContent = c === 0 ? 'Off' : c + (c === 1 ? ' copy' : ' copies');
      // Update buttons
      if (container) {
        var minusBtn = container.querySelector('[data-pool-action="minus"]');
        var plusBtn = container.querySelector('[data-pool-action="plus"]');
        if (minusBtn) {
          minusBtn.disabled = (c <= 0);
          minusBtn.onclick = function() { updatePoolCopies(shareId, c - 1); };
        }
        if (plusBtn) {
          plusBtn.disabled = (c >= 2);
          plusBtn.onclick = function() { updatePoolCopies(shareId, c + 1); };
        }
      }
    })
    .catch(function(err) {
      console.error('Pool copies update failed:', err);
    })
    .finally(function() {
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

function getShareSize(shareId) {
  var area = document.getElementById('size-area-' + shareId);
  var spinner = document.getElementById('size-spinner-' + shareId);
  if (spinner) spinner.style.display = '';

  fetch('/tab/shares/update_size/' + shareId, {
    method: 'PUT',
    headers: csrfHeaders(),
    credentials: 'same-origin'
  })
    .then(function(r) { return r.json(); })
    .then(function(data) {
      if (area) area.innerHTML = '<strong>' + data.size + '</strong>';
    })
    .catch(function(err) {
      console.error('Get size failed:', err);
      if (area) area.innerHTML = '<span class="text-danger">Error</span>';
    })
    .finally(function() {
      if (spinner) spinner.style.display = 'none';
    });
}

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
