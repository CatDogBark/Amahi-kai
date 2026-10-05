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

document.addEventListener('click', function(event) {
  var dialog = document.getElementById('whats-new');
  if (!dialog) return;

  if (event.target.closest('[data-whats-new]')) {
    event.preventDefault();
    bootstrap.Modal.getOrCreateInstance(dialog).show();
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
