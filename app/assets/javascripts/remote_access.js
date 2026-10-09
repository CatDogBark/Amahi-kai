// Network → Remote Access: the Cloudflare Tunnel (its token goes by POST, then its setup
// streams) and Tailscale (installed in its window, connected, stopped, logged out). The
// addresses come from the buttons' data-args; runSecurityAudit is in security.js.

function setupTunnel(stageUrl, streamUrl) {
  var token = document.getElementById('tunnel-token-field').value.trim();
  if (!token) { alert('Please paste your tunnel token first.'); return; }
  // The token goes in a POST body; putting it in the stream URL logged it.
  var body = new URLSearchParams({ token: token });
  fetch(stageUrl, {
    method: 'POST', headers: csrfHeaders(), credentials: 'same-origin', body: body
  }).then(function(r) {
    if (r.ok) return openInstallTerminal('tunnel-setup', streamUrl);
    return r.json().catch(function() { return {}; }).then(function(data) {
      throw new Error(data.error || ('HTTP ' + r.status));
    });
  }).catch(function(err) {
    alert('Could not send the tunnel token: ' + err.message);
  });
}

function installTailscale(streamUrl) {
  var id = 'tailscale-install';
  var modal = document.getElementById(id + '-install-modal');
  var output = document.getElementById(id + '-output');
  var cursor = document.getElementById(id + '-cursor');
  var footer = document.getElementById(id + '-install-footer');
  var terminal = document.getElementById(id + '-terminal');

  modal.style.display = 'flex';
  output.innerHTML = '';
  cursor.style.display = '';
  footer.style.display = 'none';
  footer.replaceChildren(terminalCloseButton(id));

  var source = new EventSource(withStreamToken(streamUrl));

  source.onmessage = function(e) {
    var line = document.createElement('div');
    line.className = 'term-line';
    var text = e.data;
    if (text.match(/^(Installing|Starting|Downloading)/)) { line.classList.add('step'); }
    else if (text.match(/✓/)) { line.classList.add('success'); }
    else if (text.match(/✗/)) { line.classList.add('error'); }
    else if (text.match(/⚠/)) { line.classList.add('warn'); }
    line.textContent = text;
    output.appendChild(line);
    terminal.scrollTop = terminal.scrollHeight;
  };

  // Tailscale's login address, as a link (the address comes from the server's stream)
  source.addEventListener('auth_url', function(e) {
    if (!e.data) return;
    var linkDiv = document.createElement('div');
    linkDiv.className = 'term-line';
    linkDiv.style.marginTop = '8px';
    var link = document.createElement('a');
    link.href = e.data;
    link.target = '_blank';
    link.rel = 'noopener';
    link.style.cssText = 'color:#4fc3f7;text-decoration:underline;font-weight:bold;';
    link.textContent = '→ Click here to log in to Tailscale';
    linkDiv.appendChild(link);
    output.appendChild(linkDiv);
    terminal.scrollTop = terminal.scrollHeight;
  });

  source.addEventListener('done', function() {
    source.close();
    cursor.style.display = 'none';
    footer.style.display = 'block';
  });

  source.onerror = function() {
    source.close();
    cursor.style.display = 'none';
    footer.style.display = 'block';
  };
}

function startTailscale(btn, url) {
  btn.disabled = true;
  btn.textContent = 'Connecting...';
  fetch(url, {
    method: 'POST',
    headers: { 'X-CSRF-Token': document.querySelector('meta[name=csrf-token]').content, 'Accept': 'application/json' }
  }).then(function(r) {
    if (!r.ok) throw new Error('Server returned ' + r.status);
    return r.json();
  }).then(function(data) {
    if (data.auth_url) {
      window.open(data.auth_url, '_blank');
      setTimeout(function() { window.location.reload(); }, 5000);
    } else {
      window.location.reload();
    }
  }).catch(function(err) {
    alert('Failed to connect: ' + err.message);
    btn.disabled = false;
    btn.textContent = 'Connect';
  });
}

// Stop or log out: the button's data-args name the address.
function tailscaleAction(url) {
  fetch(url, {
    method: 'POST',
    headers: { 'X-CSRF-Token': document.querySelector('meta[name=csrf-token]').content }
  }).then(function() { window.location.reload(); });
}

function tunnelAction(action, btn, url) {
  var busy = { start: 'Connecting…', stop: 'Disconnecting…', restart: 'Restarting…' };
  var label = btn ? btn.innerHTML : '';
  if (btn) {
    btn.disabled = true;
    btn.innerHTML = '<span class="spinner-border spinner-border-sm" role="status"></span> ' + busy[action];
  }
  fetch(url, {
    method: 'POST',
    headers: { 'X-CSRF-Token': document.querySelector('meta[name=csrf-token]').content, 'Accept': 'application/json' }
  }).then(function(r) {
    return r.json().catch(function() { return {}; }).then(function(data) {
      if (!r.ok) throw new Error(data.error || ('Server returned ' + r.status));
      window.location.reload();
    });
  }).catch(function(err) {
    if (btn) {
      btn.disabled = false;
      btn.innerHTML = label;
    }
    alert('Failed to ' + action + ' tunnel: ' + err.message);
  });
}
