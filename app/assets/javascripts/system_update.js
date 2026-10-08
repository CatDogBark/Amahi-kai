// System Update for admins. Anything with data-whats-new (the header's update button, the
// dashboard's notice) opens the dialog in layouts/_system_update, whose buttons install the
// update, run Repair, or check for updates. The update itself runs in the System Update
// window (startSystemUpdate, shared/_install_terminal).

// Asks the root helper to check GitHub now, then reloads the page to show what it found.
// System Status's "Check now" uses it too.
function checkForUpdates(button, url) {
  var label = button.textContent;
  var again = function(message) {
    alert(message);
    button.disabled = false;
    button.textContent = label;
  };
  button.disabled = true;
  button.textContent = 'Checking…';
  fetch(url, { method: 'POST', headers: csrfHeaders(), credentials: 'same-origin' })
    .then(function(r) { return r.json().catch(function() { return {}; }); })
    .then(function(data) {
      if (data.status === 'ok') { window.location.reload(); return; }
      again('The check for updates failed: ' + (data.error || 'no answer from Amahi-kai'));
    })
    .catch(function(err) { again('The check for updates failed: ' + err.message); });
}

// The dialog is filled in when the page loads, so a page left open (overnight, say) went on
// showing that check, its "Checked … ago" counting up past the checks made since. Its content,
// and the header button's label and dot, are fetched again when the dialog opens and when the
// tab comes back into view (at most once a minute), and swapped in when a check has run since.
var updateDialogFetchedAt = 0;
function refreshUpdateDialog() {
  var dialog = document.getElementById('whats-new');
  if (!dialog || !dialog.dataset.refreshUrl || Date.now() - updateDialogFetchedAt < 60000) return;
  if (dialog.querySelector('[data-update-action]:disabled')) return; // a check is under way
  updateDialogFetchedAt = Date.now();
  fetch(dialog.dataset.refreshUrl, { credentials: 'same-origin', headers: { 'Accept': 'application/json' } })
    .then(function(r) { return r.ok ? r.json() : null; })
    .then(function(data) {
      if (!data) return;
      var content = dialog.querySelector('.modal-content');
      if (content && (data.checked_at || '') !== (content.dataset.updateCheckedAt || '')) {
        content.innerHTML = data.html;
        content.dataset.updateCheckedAt = data.checked_at || '';
        refreshRelativeTimes();
      }
      var button = document.getElementById('update-btn');
      if (button && data.waiting) {
        button.setAttribute('aria-label', data.waiting.label);
        button.dataset.tip = data.waiting.label;
        var dot = button.querySelector('.update-dot');
        if (data.waiting.dot && !dot) {
          dot = document.createElement('span');
          dot.className = 'update-dot';
          button.appendChild(dot);
        } else if (!data.waiting.dot && dot) {
          dot.remove();
        }
      }
    })
    .catch(function() { /* keep what the page has */ });
}

document.addEventListener('visibilitychange', function() { if (!document.hidden) refreshUpdateDialog(); });

document.addEventListener('click', function(event) {
  var dialog = document.getElementById('whats-new');
  if (!dialog) return;

  if (event.target.closest('[data-whats-new]')) {
    event.preventDefault();
    bootstrap.Modal.getOrCreateInstance(dialog).show();
    refreshUpdateDialog();
    return;
  }

  var button = event.target.closest('#whats-new [data-update-action]');
  if (!button) return;
  if (button.dataset.updateAction === 'check') {
    checkForUpdates(button, button.dataset.url);
    return;
  }
  if (button.dataset.confirm && !confirm(button.dataset.confirm)) return;
  bootstrap.Modal.getOrCreateInstance(dialog).hide();
  startSystemUpdate('system-update', button.dataset.url, dialog.dataset.streamUrl);
});
