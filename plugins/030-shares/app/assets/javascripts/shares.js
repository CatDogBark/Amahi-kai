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

var SHARE_PRESETS = {
  recycle_bin: "vfs objects = recycle\nrecycle:repository = .recycle\nrecycle:keeptree = yes\nrecycle:versions = yes",
  macos: "vfs objects = fruit streams_xattr\nfruit:metadata = stream\nfruit:model = MacSamba\nfruit:posix_rename = yes\nfruit:veto_appledouble = no\nfruit:nfs_aces = no\nfruit:wipe_intentionally_left_blank_rfork = yes\nfruit:delete_empty_adfiles = yes",
  hide_dotfiles: "hide dot files = yes\nveto files = /._*/.DS_Store/",
  time_machine: "vfs objects = fruit streams_xattr\nfruit:time machine = yes\nfruit:metadata = stream\nfruit:model = TimeCapsule"
};

function toggleSharePreset(shareId, presetKey) {
  var preset = SHARE_PRESETS[presetKey];
  if (!preset) return;

  var btn = document.querySelector('#share-presets-' + shareId + ' [data-preset="' + presetKey + '"]');
  var isActive = btn && btn.classList.contains('btn-info');

  // Get current extras via textarea if visible, otherwise fetch
  var textarea = document.getElementById('extras-textarea-' + shareId);
  var current = textarea ? textarea.value : '';

  var newExtras;
  if (isActive) {
    // Remove preset lines
    var lines = current.split('\n');
    var presetLines = preset.split('\n');
    newExtras = lines.filter(function(line) {
      return presetLines.indexOf(line.trim()) === -1;
    }).join('\n').replace(/\n{3,}/g, '\n\n').trim();
  } else {
    // Add preset lines (avoid duplicates)
    var existing = current.trim();
    // Check for vfs objects conflict — merge if both use vfs objects
    var presetLines = preset.split('\n');
    var existingLines = existing.split('\n');
    var mergedLines = existingLines.slice();
    presetLines.forEach(function(pl) {
      var found = false;
      for (var i = 0; i < mergedLines.length; i++) {
        if (mergedLines[i].trim() === pl.trim()) { found = true; break; }
      }
      if (!found) mergedLines.push(pl);
    });
    newExtras = mergedLines.join('\n').trim();
  }

  // Save via API
  if (btn) btn.disabled = true;
  fetch('/shares/' + shareId + '/update_extras', {
    method: 'PUT',
    headers: Object.assign(csrfHeaders(), {'Content-Type': 'application/x-www-form-urlencoded'}),
    credentials: 'same-origin',
    body: 'share[extras]=' + encodeURIComponent(newExtras)
  })
    .then(function(r) { return r.json(); })
    .then(function(data) {
      if (data.status === 'ok' || data.status === 'not_acceptable') {
        // Update button state
        if (btn) {
          btn.classList.toggle('btn-info');
          btn.classList.toggle('btn-outline-secondary');
        }
        // Update textarea if visible
        if (textarea) textarea.value = newExtras;
      }
    })
    .catch(function(err) { console.error('Preset toggle failed:', err); })
    .finally(function() { if (btn) btn.disabled = false; });
}

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
        msg.style.display = '';
        setTimeout(function() { msg.style.display = 'none'; }, 2000);
      }
      // Update preset button states
      var container = document.getElementById('share-presets-' + shareId);
      if (container) {
        container.querySelectorAll('[data-preset]').forEach(function(btn) {
          var preset = SHARE_PRESETS[btn.dataset.preset];
          if (!preset) return;
          var allPresent = preset.split('\n').every(function(line) {
            return extras.indexOf(line.trim()) !== -1;
          });
          btn.classList.toggle('btn-info', allPresent);
          btn.classList.toggle('btn-outline-secondary', !allPresent);
        });
      }
    })
    .catch(function(err) { console.error('Save extras failed:', err); });
}

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
