// Apps plugin JS

// Initialize Bootstrap tooltips (works with both initial load and Turbo navigations)
function initTooltips() {
  document.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(function(el) {
    if (!el._tooltipInit) {
      new bootstrap.Tooltip(el);
      el._tooltipInit = true;
    }
  });
}
document.addEventListener('DOMContentLoaded', initTooltips);
document.addEventListener('turbo:load', initTooltips);
document.addEventListener('turbo:frame-load', initTooltips);

// POST action for docker app controls (start/stop/uninstall)
function dockerAppAction(url, identifier, btn) {
  if (btn) {
    btn.disabled = true;
    btn._origHTML = btn.innerHTML;
    btn.innerHTML = '<span class="spinner-border spinner-border-sm"></span>';
  }

  fetch(url, {
    method: 'POST',
    headers: csrfHeaders(),
    credentials: 'same-origin'
  })
    .then(function(r) { return r.json(); })
    .then(function(data) {
      if (data.status === 'ok') {
        // Update the row in-place
        var row = document.getElementById('docker_app_' + identifier);
        if (row) {
          var actionCell = row.querySelector('td:last-child');
          if (actionCell) {
            actionCell.innerHTML = buildAppButtons(identifier, data.app_status, data.host_port, data.name);
          }
        }
      } else {
        alert('Action failed: ' + (data.message || 'Unknown error'));
      }
    })
    .catch(function(err) {
      console.error('App action failed:', err);
      alert('Action failed — check your connection');
    })
    .finally(function() {
      if (btn) {
        btn.innerHTML = btn._origHTML || btn.innerHTML;
        btn.disabled = false;
      }
    });
}

function buildAppButtons(identifier, status, hostPort, name) {
  if (status === 'running') {
    var html = '<div class="d-flex gap-1 justify-content-end">';
    var row = document.getElementById('docker_app_' + identifier);
    var proxyMode = row ? row.getAttribute('data-proxy-mode') : 'proxy';
    if (hostPort && proxyMode === 'subdomain') {
      html += '<span class="text-secondary small me-1">Needs subdomain</span><button class="btn btn-sm btn-outline-secondary disabled" type="button">🔗</button>';
    } else if (hostPort) {
      html += '<a class="btn btn-sm btn-success" href="/app/' + identifier + '" target="_blank">Open</a>';
    }
    html += '<button class="btn btn-sm btn-outline-danger" onclick="dockerAppAction(\'/tab/apps/docker/stop/' + identifier + '\', \'' + identifier + '\', this)">Stop</button>';
    html += '</div>';
    return html;
  } else if (status === 'stopped') {
    var html = '<div class="d-flex gap-1 justify-content-end">';
    html += '<button class="btn btn-sm btn-outline-success" onclick="dockerAppAction(\'/tab/apps/docker/start/' + identifier + '\', \'' + identifier + '\', this)">Start</button>';
    html += '<button class="btn btn-sm btn-outline-danger" onclick="if(confirm(\'Uninstall ' + name + '?\')){dockerAppAction(\'/tab/apps/docker/uninstall/' + identifier + '\', \'' + identifier + '\', this)}">Uninstall</button>';
    html += '</div>';
    return html;
  } else if (status === 'available') {
    return '<button class="btn btn-sm btn-primary" onclick="openAppInstall(\'' + identifier + '\', \'/tab/apps/docker/install_stream/' + identifier + '\', \'' + name + '\')">Install</button>';
  }
  return '';
}
