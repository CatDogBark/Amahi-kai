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
  if (copies === 0 && !confirm("Turn the pool off for this share? If it has files on the pool drives, Greyhole first moves them back into the share's folder on the system disk, which needs room for them.")) return;
  if (spinner) spinner.style.display = '';

  fetch('/shares/' + shareId + '/update_disk_pool_copies', {
    method: 'PUT',
    headers: Object.assign(csrfHeaders(), {'Content-Type': 'application/x-www-form-urlencoded'}),
    credentials: 'same-origin',
    body: 'copies=' + copies
  })
    .then(function(r) { return r.json(); })
    .then(function(data) {
      if (data.status === 'error') alert(data.message);
      // Turning off while Greyhole moves the files back: the page shows it, and updates itself.
      if (data.removing) { window.location.reload(); return; }
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

// Advanced → Samba settings: saves the share's raw settings.
function submitExtras(shareId, form) {
  var textarea = document.getElementById('extras-textarea-' + shareId);
  var msg = document.getElementById('extras-msg-' + shareId);
  var extras = textarea ? textarea.value : '';

  fetch('/shares/' + shareId + '/update_extras', {
    method: 'PUT',
    headers: Object.assign(csrfHeaders(), {'Content-Type': 'application/x-www-form-urlencoded'}),
    credentials: 'same-origin',
    body: 'share[extras]=' + encodeURIComponent(extras)
  })
    .then(function(r) { return r.json(); })
    .then(function(data) {
      if (msg) {
        msg.textContent = data.status === 'ok' ? 'Saved!' : 'Not saved: ' + (data.message || 'Samba refused it');
        msg.className = 'ms-2 small ' + (data.status === 'ok' ? 'text-success' : 'text-danger');
        msg.style.display = '';
        setTimeout(function() { msg.style.display = 'none'; }, 4000);
      }
    })
    .catch(function(err) { console.error('Save extras failed:', err); });
}

function getShareSize(shareId) {
  var area = document.getElementById('size-area-' + shareId);
  var spinner = document.getElementById('size-spinner-' + shareId);
  if (spinner) spinner.style.display = '';

  fetch('/shares/' + shareId + '/update_size', {
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
