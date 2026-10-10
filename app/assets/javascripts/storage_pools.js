// Disks → ZFS Pools (disks/pools). The create form works out which layouts the ticked drives
// allow, with the space they'd give and how many may fail, then asks the server to create
// the pool. data-storage-install buttons open the install window; data-storage-post buttons
// (Scrub now, Check now) post to their URL, with their data-name, and reload.
// data-pool-dialog buttons open the replace, add-drives, delete and roll-back dialogs
// (disks/_pool_dialogs). While a scrub or resilver runs, the page reloads every 30 seconds.

(function() {
  // Sizes as Rails' number_to_human_size writes them (1024-based, "2.73 TB").
  function humanSize(bytes) {
    var units = ['Bytes', 'KB', 'MB', 'GB', 'TB', 'PB'];
    var i = 0;
    while (bytes >= 1024 && i < units.length - 1) { bytes /= 1024; i++; }
    return (i === 0 ? bytes : parseFloat(bytes.toPrecision(3))) + ' ' + units[i];
  }

  function fits(layout, count) {
    return count >= layout.min && (!layout.pairs || count % 2 === 0);
  }

  // Usable space before ZFS's own overhead: every drive counts as the smallest one.
  function usable(layout, count, smallest) {
    if (layout.key === 'mirror') return smallest;
    if (layout.key === 'striped_mirrors') return (count / 2) * smallest;
    return (count - layout.parity) * smallest;
  }

  function survives(layout, count) {
    if (layout.key === 'striped_mirrors') return 'one drive failing in each pair';
    var n = layout.key === 'mirror' ? count - 1 : layout.parity;
    return n === 1 ? 'one drive failing' : n + ' drives failing';
  }

  function suggested(count) {
    if (count === 2) return 'mirror';
    if (count <= 5) return 'raidz1';
    return 'raidz2';
  }

  function chosenDrives(form) {
    return Array.prototype.slice.call(form.querySelectorAll('input[name="devices[]"]:checked'));
  }

  function update(form) {
    var drives = chosenDrives(form);
    var count = drives.length;
    var smallest = Math.min.apply(null, drives.map(function(d) { return parseInt(d.dataset.size, 10) || 0; }));
    var layouts = JSON.parse(form.dataset.layouts);
    layouts.forEach(function(layout) {
      var radio = form.querySelector('input[name="layout"][value="' + layout.key + '"]');
      var info = form.querySelector('[data-layout-info="' + layout.key + '"]');
      var ok = fits(layout, count);
      radio.disabled = !ok;
      if (!ok) radio.checked = false;
      info.textContent = ok
        ? humanSize(usable(layout, count, smallest)) + ' usable · survives ' + survives(layout, count)
        : 'needs ' + layout.min + ' or more drives' + (layout.pairs ? ', in pairs' : '');
      form.querySelector('[data-layout-suggested="' + layout.key + '"]').hidden = !(count >= 2 && suggested(count) === layout.key);
    });
    var name = form.querySelector('#pool-name').value.trim();
    var layout = form.querySelector('input[name="layout"]:checked');
    form.querySelector('#create-pool-btn').disabled = !(layout && name && form.querySelector('#pool-erase').checked);
  }

  function submit(form) {
    var devices = chosenDrives(form).map(function(d) { return d.value; });
    var layout = form.querySelector('input[name="layout"]:checked');
    var name = form.querySelector('#pool-name').value.trim();
    var button = form.querySelector('#create-pool-btn');
    var error = form.querySelector('#pool-form-error');
    var layoutName = form.querySelector('label[for="' + layout.id + '"] strong').textContent;
    if (!confirm('Create the ' + layoutName + ' pool "' + name + '" on ' + devices.join(', ') +
                 '?\n\nEverything on these drives is erased.')) return;

    var fail = function(message) {
      error.textContent = message;
      button.textContent = 'Create pool';
      update(form);
    };
    error.textContent = '';
    button.disabled = true;
    button.textContent = 'Creating…';
    fetch(form.action, {
      method: 'POST', credentials: 'same-origin',
      headers: Object.assign({ 'Content-Type': 'application/json', 'Accept': 'application/json' }, csrfHeaders()),
      body: JSON.stringify({ name: name, layout: layout.value, devices: devices })
    }).then(function(r) { return r.json().catch(function() { return {}; }); })
      .then(function(data) {
        if (data.status === 'ok') { window.location.reload(); return; }
        fail(data.error || 'No answer from Amahi-kai');
      })
      .catch(function(err) { fail(err.message); });
  }

  // Posts JSON to +url+ and reloads the page, or passes the error to +fail+.
  function postJSON(url, body, fail) {
    fetch(url, {
      method: 'POST', credentials: 'same-origin',
      headers: Object.assign({ 'Content-Type': 'application/json', 'Accept': 'application/json' }, csrfHeaders()),
      body: JSON.stringify(body)
    }).then(function(r) { return r.json().catch(function() { return {}; }); })
      .then(function(data) {
        if (data.status === 'ok') { window.location.reload(); return; }
        fail(data.error || 'No answer from Amahi-kai');
      })
      .catch(function(err) { fail(err.message); });
  }

  // --- The pool dialogs ---

  function camel(name) {
    return name.replace(/-([a-z])/g, function(_m, c) { return c.toUpperCase(); });
  }

  function openDialog(button) {
    var dialog = document.getElementById(button.dataset.poolDialog + '-dialog');
    if (!dialog) return;
    dialog.poolData = Object.assign({}, button.dataset);
    dialog.querySelectorAll('[data-fill]').forEach(function(el) {
      el.textContent = dialog.poolData[camel(el.dataset.fill)] || '';
    });
    dialog.querySelectorAll('input[type=checkbox], input[type=radio]').forEach(function(box) { box.checked = false; });
    dialog.querySelectorAll('input[type=text]').forEach(function(text) { text.value = ''; });
    dialog.querySelector('[data-dialog-error]').textContent = '';
    updateDialog(dialog);
    bootstrap.Modal.getOrCreateInstance(dialog).show();
  }

  function chosen(dialog) {
    return Array.prototype.slice.call(dialog.querySelectorAll('.list-group input:checked'));
  }

  function updateDialog(dialog) {
    var data = dialog.poolData || {};
    var erase = dialog.querySelector('[data-confirm-erase]');
    var ready = false;
    if (dialog.id === 'replace-dialog') {
      ready = chosen(dialog).length === 1 && erase.checked;
    } else if (dialog.id === 'add-dialog') {
      var drives = chosen(dialog);
      var width = parseInt(data.width, 10);
      var estimate = dialog.querySelector('[data-add-estimate]');
      if (drives.length === width) {
        var smallest = Math.min.apply(null, drives.map(function(d) { return parseInt(d.dataset.size, 10) || 0; }));
        var usable = (width - parseInt(data.parity, 10)) * smallest;
        estimate.textContent = 'Adds about ' + humanSize(usable) + ' of usable space.';
      } else {
        estimate.textContent = drives.length + ' of ' + width + ' drives chosen.';
      }
      ready = drives.length === width && erase.checked;
    } else if (dialog.id === 'destroy-dialog' || dialog.id === 'rollback-dialog') {
      ready = dialog.querySelector('[data-confirm-name]').value === data.name;
    }
    dialog.querySelector('[data-dialog-submit]').disabled = !ready;
  }

  function submitDialog(dialog) {
    var data = dialog.poolData;
    var button = dialog.querySelector('[data-dialog-submit]');
    var label = button.textContent;
    var body = { name: data.name };
    if (dialog.id === 'replace-dialog') {
      body.old = data.old;
      body.new = chosen(dialog)[0].value;
    } else if (dialog.id === 'add-dialog') {
      body.devices = chosen(dialog).map(function(d) { return d.value; });
    } else {
      if (data.snapshot) body.snapshot = data.snapshot;
      body.confirm = dialog.querySelector('[data-confirm-name]').value;
    }
    button.disabled = true;
    button.textContent = 'Working…';
    dialog.querySelector('[data-dialog-error]').textContent = '';
    postJSON(dialog.dataset.url, body, function(message) {
      dialog.querySelector('[data-dialog-error]').textContent = message;
      button.textContent = label;
      updateDialog(dialog);
    });
  }

  document.addEventListener('change', function(event) {
    var form = event.target.closest('#pool-form');
    if (form) { form.dataset.touched = 'true'; update(form); }
    var dialog = event.target.closest('.modal[id$="-dialog"]');
    if (dialog && dialog.poolData) updateDialog(dialog);
  });

  document.addEventListener('input', function(event) {
    var form = event.target.closest('#pool-form');
    if (form) { form.dataset.touched = 'true'; update(form); }
    var dialog = event.target.closest('.modal[id$="-dialog"]');
    if (dialog && dialog.poolData) updateDialog(dialog);
  });

  document.addEventListener('submit', function(event) {
    var policy = event.target.closest('[data-snapshot-policy]');
    if (policy) {
      event.preventDefault();
      var save = policy.querySelector('button[type=submit]');
      save.disabled = true;
      postJSON(policy.dataset.url, {
        name: policy.dataset.name,
        hourly: parseInt(policy.elements.hourly.value, 10),
        daily: parseInt(policy.elements.daily.value, 10)
      }, function(message) { alert(message); save.disabled = false; });
      return;
    }
    var form = event.target.closest('#pool-form');
    if (!form) return;
    event.preventDefault();
    submit(form);
  });

  // data-name, data-snapshot and data-drive go in the body; data-confirm asks first.
  function post(button) {
    if (button.dataset.confirm && !confirm(button.dataset.confirm)) return;
    var label = button.textContent;
    var body = {};
    if (button.dataset.name) body.name = button.dataset.name;
    if (button.dataset.snapshot) body.snapshot = button.dataset.snapshot;
    if (button.dataset.drive) body.drive = button.dataset.drive;
    button.disabled = true;
    button.textContent = 'Working…';
    postJSON(button.dataset.storagePost, body, function(message) {
      alert(message);
      button.disabled = false;
      button.textContent = label;
    });
  }

  document.addEventListener('click', function(event) {
    var install = event.target.closest('[data-storage-install]');
    if (install) openInstallTerminal('storage-install', install.dataset.storageInstall);
    var action = event.target.closest('[data-storage-post]');
    if (action) post(action);
    var opener = event.target.closest('[data-pool-dialog]');
    if (opener) openDialog(opener);
    var submit = event.target.closest('[data-dialog-submit]');
    if (submit) submitDialog(submit.closest('.modal'));
  });

  // While a scrub or resilver runs: reload every 30 seconds, unless a dialog is open or the
  // create form has been touched.
  function refreshWhileScanning() {
    setTimeout(function() {
      var form = document.getElementById('pool-form');
      var busy = document.querySelector('.modal.show') || (form && form.dataset.touched);
      if (busy) refreshWhileScanning(); else window.location.reload();
    }, 30000);
  }

  document.addEventListener('DOMContentLoaded', function() {
    var form = document.getElementById('pool-form');
    if (form) update(form);
    if (document.querySelector('[data-pool-scanning]')) refreshWhileScanning();
  });
})();
