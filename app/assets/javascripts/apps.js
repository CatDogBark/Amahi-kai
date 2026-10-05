// Apps plugin JS

// Apps (app/views/apps): the buttons post to the apps actions, then the page reloads to show the
// app's new state. Copy buttons (data-copy) copy an app's generated password or key.

function dockerAppAction(url, btn) {
  if (btn) {
    btn.disabled = true;
    btn.innerHTML = '<span class="spinner-border spinner-border-sm"></span>';
  }
  fetch(url, { method: 'POST', headers: csrfHeaders(), credentials: 'same-origin' })
    .then(function(r) { return r.json().catch(function() { return {}; }); })
    .then(function(data) {
      if (data.status !== 'ok') alert('That didn\'t work: ' + (data.message || 'no answer from Amahi-kai'));
      window.location.reload();
    })
    .catch(function(err) {
      alert('That didn\'t work: ' + err.message);
      window.location.reload();
    });
}

// The clipboard API needs HTTPS, and the LAN page is plain HTTP, so copy through a selected
// text field there.
document.addEventListener('click', function(event) {
  var button = event.target.closest('[data-copy]');
  if (!button) return;
  var text = button.dataset.copy;
  var done = function() { button.textContent = 'Copied'; setTimeout(function() { button.textContent = 'Copy'; }, 1500); };
  if (navigator.clipboard && window.isSecureContext) {
    navigator.clipboard.writeText(text).then(done);
    return;
  }
  var field = document.createElement('textarea');
  field.value = text;
  field.style.position = 'fixed';
  field.style.opacity = '0';
  document.body.appendChild(field);
  field.select();
  try { document.execCommand('copy'); done(); } finally { field.remove(); }
});

// Installing an app: the install window (shared/install_terminal), titled with the app's name.
function openAppInstall(identifier, url, name) {
  var title = document.querySelector('#app-install-modal [style*="font-family:monospace"]');
  if (title) title.textContent = 'Installing ' + (name || identifier) + '...';
  openInstallTerminal('app', url);
}

// Choosing an app's shares (_shares_dialog) before it's installed, or installed again with new
// ones. Shares Greyhole pools, and every share of an app that only reads, stay read only.
document.addEventListener('click', function(event) {
  var button = event.target.closest('[data-app-shares]');
  if (button) openShareDialog(button);
});

function openShareDialog(button) {
  var dialog = document.getElementById('app-shares-dialog');
  var name = button.dataset.appName;
  var writes = button.dataset.writes === 'true';
  var current = JSON.parse(button.dataset.current || '[]');
  var rows = Array.prototype.slice.call(dialog.querySelectorAll('[data-share]'));

  dialog.querySelectorAll('[data-fill="name"]').forEach(function(el) { el.textContent = name; });
  dialog.querySelector('[data-fill="verb"]').textContent = button.dataset.verb;
  dialog.querySelector('[data-role="read-only-note"]').hidden = writes;
  rows.forEach(function(row) {
    var given = current.filter(function(share) { return share.name === row.dataset.share; })[0];
    var pooled = row.dataset.pooled === 'true';
    row.querySelector('[data-role="give"]').checked = !!given;
    row.querySelector('[data-role="access"]').value = given && given.write ? 'write' : 'read';
    row.querySelector('[data-role="access"]').hidden = !writes || pooled;
    row.querySelector('[data-role="pooled-note"]').hidden = !writes || !pooled;
  });

  dialog.querySelector('[data-role="confirm"]').onclick = function() {
    var params = [];
    rows.forEach(function(row) {
      if (!row.querySelector('[data-role="give"]').checked) return;
      var share = encodeURIComponent(row.dataset.share);
      params.push('share[]=' + share);
      var access = row.querySelector('[data-role="access"]');
      if (!access.hidden && access.value === 'write') params.push('write[]=' + share);
    });
    bootstrap.Modal.getOrCreateInstance(dialog).hide();
    openAppInstall(button.dataset.appShares, button.dataset.url + (params.length ? '?' + params.join('&') : ''), name);
  };
  bootstrap.Modal.getOrCreateInstance(dialog).show();
}
