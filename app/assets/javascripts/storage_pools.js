// Disks → ZFS Pools (disks/pools). The create form works out which layouts the ticked drives
// allow, with the space they'd give and how many may fail, then asks the server to create
// the pool. data-storage-install buttons open the install window; data-storage-post buttons
// (Scrub now, Check now) post to their URL, with their data-name, and reload.

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

  document.addEventListener('change', function(event) {
    var form = event.target.closest('#pool-form');
    if (form) update(form);
  });

  document.addEventListener('input', function(event) {
    var form = event.target.closest('#pool-form');
    if (form) update(form);
  });

  document.addEventListener('submit', function(event) {
    var form = event.target.closest('#pool-form');
    if (!form) return;
    event.preventDefault();
    submit(form);
  });

  function post(button) {
    var label = button.textContent;
    button.disabled = true;
    button.textContent = 'Working…';
    fetch(button.dataset.storagePost, {
      method: 'POST', credentials: 'same-origin',
      headers: Object.assign({ 'Content-Type': 'application/json', 'Accept': 'application/json' }, csrfHeaders()),
      body: JSON.stringify(button.dataset.name ? { name: button.dataset.name } : {})
    }).then(function(r) { return r.json().catch(function() { return {}; }); })
      .then(function(data) {
        if (data.status === 'ok') { window.location.reload(); return; }
        throw new Error(data.error || 'No answer from Amahi-kai');
      })
      .catch(function(err) {
        alert(err.message);
        button.disabled = false;
        button.textContent = label;
      });
  }

  document.addEventListener('click', function(event) {
    var install = event.target.closest('[data-storage-install]');
    if (install) openInstallTerminal('storage-install', install.dataset.storageInstall);
    var action = event.target.closest('[data-storage-post]');
    if (action) post(action);
  });

  document.addEventListener('DOMContentLoaded', function() {
    var form = document.getElementById('pool-form');
    if (form) update(form);
  });
})();
