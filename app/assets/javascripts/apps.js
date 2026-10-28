// Apps plugin JS

// Apps (app/views/apps): the buttons post to the apps actions, then the page reloads to show the
// app's new state. On an app's own page, a password or key Amahi-kai made for it stays hidden
// until Show (data-secret-toggle), and Copy (data-copy) copies it either way.

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

document.addEventListener('click', function(event) {
  var button = event.target.closest('[data-secret-toggle]');
  if (!button) return;
  var secret = button.closest('.kai-secret');
  var show = button.getAttribute('aria-pressed') !== 'true';
  secret.querySelector('[data-secret-value]').hidden = !show;
  secret.querySelectorAll('[data-secret-mask]').forEach(function(mask) { mask.hidden = show; });
  button.setAttribute('aria-pressed', String(show));
  button.textContent = show ? 'Hide' : 'Show';
});

// Installing an app: the install window (shared/install_terminal), titled with the app's name.
function openAppInstall(identifier, url, name, heading) {
  var title = document.querySelector('#app-install-modal [style*="font-family:monospace"]');
  if (title) title.textContent = heading || 'Installing ' + (name || identifier) + '...';
  openInstallTerminal('app', url);
}

// Update and Undo update (data-app-stream): after their confirm, they run in the install window.
document.addEventListener('click', function(event) {
  var button = event.target.closest('[data-app-stream]');
  if (!button) return;
  if (button.dataset.confirm && !confirm(button.dataset.confirm)) return;
  openAppInstall(button.dataset.appStream, button.dataset.url, null, button.dataset.title);
});

// Choosing an app's shares (_shares_dialog) before it's installed, or installed again with new
// ones: each share all of it, or only some of its folders. Shares Greyhole pools, and every share
// of an app that only reads, stay read only. An app that doesn't work with files in shares
// (data-uses-shares false) installs without asking, unless it has a ZFS pool to choose or was
// given shares before.
document.addEventListener('click', function(event) {
  var button = event.target.closest('[data-app-shares]');
  if (!button) return;
  if (button.dataset.usesShares === 'false' && !button.dataset.storage && JSON.parse(button.dataset.current || '[]').length === 0) {
    openAppInstall(button.dataset.appShares, button.dataset.url, button.dataset.appName, button.dataset.title);
    return;
  }
  openShareDialog(button);
});

function openShareDialog(button) {
  var dialog = document.getElementById('app-shares-dialog');
  var name = button.dataset.appName;
  var writes = button.dataset.writes === 'true';
  var current = JSON.parse(button.dataset.current || '[]');
  var rows = Array.prototype.slice.call(dialog.querySelectorAll('[data-share]'));
  // An app that doesn't work with shares is here for its pool only, or to drop shares given before
  var asksShares = button.dataset.usesShares !== 'false' || current.length > 0;
  shareDialogEvents(dialog);

  dialog.querySelector('[data-role="shares-part"]').hidden = !asksShares;
  dialog.querySelector('[data-fill="title"]').textContent = asksShares ? 'Shares for' : 'Storage for';
  dialog.querySelectorAll('[data-fill="name"]').forEach(function(el) { el.textContent = name; });
  dialog.querySelector('[data-fill="verb"]').textContent = button.dataset.verb;
  var storage = storageChoice(dialog, button);
  dialog.querySelector('[data-role="read-only-note"]').hidden = writes;
  rows.forEach(function(row) {
    // Share names don't depend on case (the helper, the share's delete check and MariaDB all ignore it)
    var given = current.filter(function(share) { return share.name.toLowerCase() === row.dataset.share.toLowerCase(); });
    var whole = given.filter(function(share) { return !share.folder; })[0];
    var pooled = row.dataset.pooled === 'true';
    row.dataset.canWrite = String(writes && !pooled);
    row.querySelector('[data-role="give"]').checked = given.length > 0;
    row.querySelector('[data-role="access"]').value = whole && whole.write ? 'write' : 'read';
    row.querySelector('[data-role="pooled-note"]').hidden = !writes || !pooled;
    var folders = shareFoldersRow(row);
    folders.querySelector('[data-role="folder-list"]').replaceChildren();
    folders.querySelector('[data-role="browser"]').hidden = true;
    given.filter(function(share) { return share.folder; }).forEach(function(share) { addShareFolder(row, share.folder, share.write); });
    setShareScope(row, given.length > 0 && !whole ? 'folders' : 'all');
  });

  dialog.querySelector('[data-role="confirm"]').onclick = function() {
    var params = [];
    var missing = null;
    if (storage.value()) params.push('pool=' + encodeURIComponent(storage.value()));
    rows.forEach(function(row) {
      if (!row.querySelector('[data-role="give"]').checked) return;
      var folders = shareFoldersRow(row);
      var given = [];
      if (folders.querySelector('[data-role="scope"]:checked').value === 'all') {
        given.push({ path: row.dataset.share, write: row.querySelector('[data-role="access"]').value === 'write' });
      } else {
        folders.querySelectorAll('[data-folder]').forEach(function(item) {
          var access = item.querySelector('select');
          given.push({ path: row.dataset.share + '/' + item.dataset.folder, write: !!access && access.value === 'write' });
        });
        folders.querySelector('[data-role="folders-needed"]').hidden = given.length > 0;
        if (!given.length) missing = missing || row;
      }
      given.forEach(function(share) {
        params.push('share[]=' + encodeURIComponent(share.path));
        if (share.write && row.dataset.canWrite === 'true') params.push('write[]=' + encodeURIComponent(share.path));
      });
    });
    if (missing) return;
    bootstrap.Modal.getOrCreateInstance(dialog).hide();
    openAppInstall(button.dataset.appShares, button.dataset.url + (params.length ? '?' + params.join('&') : ''), name);
  };
  bootstrap.Modal.getOrCreateInstance(dialog).show();
}

// The row under a share's row: all of it, or the folders chosen and the browser to choose more.
function shareFoldersRow(row) {
  return row.nextElementSibling;
}

// All of the share or only some folders, shown while the share is given; the share's own access
// (read only, or read and write) is for all of it, and each folder has its own.
function setShareScope(row, scope) {
  var folders = shareFoldersRow(row);
  var given = row.querySelector('[data-role="give"]').checked;
  folders.querySelector('[data-role="scope"][value="' + scope + '"]').checked = true;
  folders.hidden = !given;
  folders.querySelector('[data-role="folders"]').hidden = scope !== 'folders';
  folders.querySelector('[data-role="folders-needed"]').hidden = true;
  row.querySelector('[data-role="access"]').hidden = row.dataset.canWrite !== 'true' || scope !== 'all';
}

// A folder chosen (its path in the share), with its own access for an app that may write there.
function addShareFolder(row, folder, write) {
  var item = document.createElement('li');
  item.className = 'd-flex align-items-center gap-2 mb-1';
  item.dataset.folder = folder;
  var label = document.createElement('span');
  label.textContent = '📁 ' + folder;
  item.appendChild(label);
  if (row.dataset.canWrite === 'true') {
    var access = row.querySelector('[data-role="access"]').cloneNode(true);
    access.hidden = false;
    access.removeAttribute('data-role');
    access.setAttribute('aria-label', folder + ' access');
    access.value = write ? 'write' : 'read';
    item.appendChild(access);
  }
  var remove = document.createElement('button');
  remove.type = 'button';
  remove.className = 'btn btn-sm btn-link text-danger p-0';
  remove.dataset.role = 'remove-folder';
  remove.setAttribute('aria-label', 'Remove ' + folder);
  remove.textContent = '×';
  item.appendChild(remove);
  shareFoldersRow(row).querySelector('[data-role="folder-list"]').appendChild(item);
}

// The folder browser, at +path+ in the row's share: its folders (apps/share_folders), a way back
// up, and Choose for the folder it's at.
function browseShareFolders(row, path) {
  var dialog = document.getElementById('app-shares-dialog');
  var browser = shareFoldersRow(row).querySelector('[data-role="browser"]');
  var crumbs = browser.querySelector('[data-role="crumbs"]');
  var entries = browser.querySelector('[data-role="entries"]');
  var choose = browser.querySelector('[data-role="choose-here"]');
  browser.hidden = false;
  browser.dataset.path = path;
  choose.disabled = !path;
  choose.textContent = path ? 'Choose ' + path : 'Open a folder to choose it';
  crumbs.replaceChildren();
  var parts = path ? path.split('/') : [];
  [row.dataset.share].concat(parts).forEach(function(part, index) {
    if (index) crumbs.appendChild(document.createTextNode(' / '));
    var crumb = document.createElement('button');
    crumb.type = 'button';
    crumb.className = 'btn btn-link btn-sm p-0 align-baseline';
    crumb.dataset.role = 'crumb';
    crumb.dataset.path = parts.slice(0, index).join('/');
    crumb.textContent = part;
    crumbs.appendChild(crumb);
  });
  entries.textContent = 'Reading the folders…';
  var url = dialog.dataset.foldersUrl + '?share=' + encodeURIComponent(row.dataset.share) + '&path=' + encodeURIComponent(path);
  fetch(url, { credentials: 'same-origin', headers: { Accept: 'application/json' } })
    .then(function(response) { return response.json().then(function(body) { return { ok: response.ok, body: body }; }); })
    .then(function(reply) {
      if (browser.dataset.path !== path) return; // another folder was opened meanwhile
      entries.replaceChildren();
      if (!reply.ok) { entries.textContent = reply.body.error || "Couldn't read the folders"; return; }
      if (!reply.body.folders.length) { entries.textContent = 'No folders in here.'; return; }
      reply.body.folders.forEach(function(folder) {
        var entry = document.createElement('button');
        entry.type = 'button';
        entry.className = 'btn btn-sm btn-outline-secondary';
        entry.dataset.role = 'folder-entry';
        entry.dataset.path = path ? path + '/' + folder : folder;
        entry.textContent = '📁 ' + folder;
        entries.appendChild(entry);
      });
    })
    .catch(function() { entries.textContent = "Couldn't read the folders"; });
}

// Why +folder+ can't be added beside the folders chosen already (the root helper refuses the
// same), or null.
function shareFolderClash(row, folder) {
  var chosen = Array.prototype.map.call(shareFoldersRow(row).querySelectorAll('[data-folder]'), function(item) { return item.dataset.folder; });
  for (var i = 0; i < chosen.length; i++) {
    if (chosen[i] === folder) return folder + ' is chosen already';
    if (folder.indexOf(chosen[i] + '/') === 0) return folder + ' is inside ' + chosen[i] + ', chosen already';
    if (chosen[i].indexOf(folder + '/') === 0) return chosen[i] + ', chosen already, is inside ' + folder + ': remove it first';
  }
  return null;
}

// The dialog's own controls, listened to once.
function shareDialogEvents(dialog) {
  if (dialog.dataset.listening) return;
  dialog.dataset.listening = 'true';
  dialog.addEventListener('change', function(event) {
    var target = event.target;
    var row = target.closest('[data-share]') || (target.closest('[data-share-folders]') || {}).previousElementSibling;
    if (!row) return;
    if (target.matches('[data-role="give"]')) {
      setShareScope(row, shareFoldersRow(row).querySelector('[data-role="scope"]:checked').value);
    } else if (target.matches('[data-role="scope"]')) {
      setShareScope(row, target.value);
      if (target.value === 'folders' && !shareFoldersRow(row).querySelector('[data-folder]')) browseShareFolders(row, '');
    }
  });
  dialog.addEventListener('click', function(event) {
    var target = event.target.closest('button');
    var folders = target && target.closest('[data-share-folders]');
    if (!folders) return;
    var row = folders.previousElementSibling;
    var browser = folders.querySelector('[data-role="browser"]');
    switch (target.dataset.role) {
      case 'add-folder': browseShareFolders(row, ''); break;
      case 'folder-entry':
      case 'crumb': browseShareFolders(row, target.dataset.path); break;
      case 'browser-cancel': browser.hidden = true; break;
      case 'remove-folder': target.closest('[data-folder]').remove(); break;
      case 'choose-here': {
        var clash = shareFolderClash(row, browser.dataset.path);
        if (clash) { browser.querySelector('[data-role="entries"]').textContent = clash; break; }
        addShareFolder(row, browser.dataset.path, false);
        folders.querySelector('[data-role="folders-needed"]').hidden = true;
        browser.hidden = true;
        break;
      }
    }
  });
}

// Storage, for an app that keeps data on a ZFS pool (P4.6; data-storage: required or optional): the
// pool its data is on already (data-storage-pool), or one to choose, the first time. An app that
// needs one can't be installed before there's a pool. Returns { value() } for the install.
function storageChoice(dialog, button) {
  var need = button.dataset.storage;
  var kept = button.dataset.storagePool;
  var box = dialog.querySelector('[data-role="storage"]');
  var select = box.querySelector('[data-role="pool"]');
  var none = box.querySelector('[data-role="pool-none"]');
  var pools = select.options.length - 1;
  var choosing = !!need && !kept && pools > 0;

  box.hidden = !need;
  box.querySelector('[data-fill="storage-pool"]').textContent = kept || '';
  box.querySelector('[data-role="storage-kept"]').hidden = !kept;
  box.querySelector('[data-role="storage-choose"]').hidden = !choosing;
  box.querySelector('[data-role="storage-missing"]').hidden = !need || !!kept || pools > 0 || need !== 'required';
  none.hidden = none.disabled = need === 'required';
  select.selectedIndex = need === 'required' && pools > 0 ? 1 : 0;
  dialog.querySelector('[data-role="confirm"]').disabled = need === 'required' && !kept && pools === 0;
  return { value: function() { return choosing ? select.value : ''; } };
}

// Docker's on/off switch on the Apps pages: the slider moves at once, then the server is
// asked; it goes back if that fails. The addresses come from the switch's data-args.
function dockerStatusText(statusEl, running, text) {
  statusEl.textContent = 'Docker ';
  var mark = document.createElement('span');
  mark.className = 'ms-1';
  mark.style.color = running ? 'var(--kai-success, #68d391)' : 'var(--kai-muted, #a0aec0)';
  mark.textContent = text;
  statusEl.appendChild(mark);
}

function toggleDocker(cb, startUrl, stopUrl) {
  var url = cb.checked ? startUrl : stopUrl;
  var statusEl = cb.closest('.d-flex').querySelector('.docker-status');
  var knob = cb.closest('.docker-toggle-switch').querySelector('.docker-knob');
  var slider = cb.closest('.docker-toggle-switch').querySelector('.docker-slider');
  var paint = function(running) {
    knob.style.left = running ? '22px' : '2px';
    slider.style.background = running ? 'var(--kai-success, #68d391)' : '#4a5568';
  };

  paint(cb.checked);
  dockerStatusText(statusEl, cb.checked, cb.checked ? '● Starting...' : '○ Stopping...');

  fetch(url, {
    method: 'POST',
    headers: { 'X-CSRF-Token': document.querySelector('meta[name=csrf-token]').content, 'Accept': 'application/json' },
    credentials: 'same-origin'
  }).then(function() {
    dockerStatusText(statusEl, cb.checked, cb.checked ? '● Running' : '○ Stopped');
  }).catch(function() {
    cb.checked = !cb.checked;
    paint(cb.checked);
    dockerStatusText(statusEl, cb.checked, cb.checked ? '● Running' : '○ Stopped');
  });
}

document.addEventListener('DOMContentLoaded', function() {
  var cb = document.getElementById('docker-toggle');
  if (cb && cb.checked) {
    cb.closest('.docker-toggle-switch').querySelector('.docker-slider').style.background = 'var(--kai-success, #68d391)';
  }
});
