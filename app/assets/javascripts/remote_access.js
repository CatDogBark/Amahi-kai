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

function installTailscale(streamUrl, statusUrl) {
  var id = 'tailscale-install';
  var modal = document.getElementById(id + '-install-modal');
  var output = document.getElementById(id + '-output');
  var cursor = document.getElementById(id + '-cursor');
  var footer = document.getElementById(id + '-install-footer');
  var terminal = document.getElementById(id + '-terminal');

  modal.style.display = 'flex';
  setTerminalState(id, 'running');
  setTerminalStatus(id, '');
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

  // Tailscale's sign-in page (its address comes from the server's stream), as a link to click, and
  // the window waits for the sign-in
  source.addEventListener('auth_url', function(e) {
    if (!e.data) return;
    var line = document.createElement('div');
    line.className = 'term-line step';
    tailscaleSignIn(line, e.data);
    output.appendChild(line);
    terminal.scrollTop = terminal.scrollHeight;
    waitForTailscale(statusUrl);
  });

  source.addEventListener('done', function() {
    source.close();
    setTerminalState(id, 'done');
    setTerminalStatus(id, '✓ Done', 'success');
    cursor.style.display = 'none';
    footer.style.display = 'block';
  });

  source.onerror = function() {
    source.close();
    setTerminalState(id, 'failed');
    setTerminalStatus(id, '✗ Connection lost', 'error');
    cursor.style.display = 'none';
    footer.style.display = 'block';
  };
}

// Connect. When the NAS isn't in a tailnet yet, Tailscale gives a sign-in page: it's shown as a
// link to click, never opened by the page. A tab a script opens seconds after the click is a
// pop-up to the browser, and Firefox blocked it. The page then waits for the sign-in, done in
// that tab (or on any device), and reloads once Tailscale is connected.
function startTailscale(btn, url, statusUrl) {
  btn.disabled = true;
  btn.textContent = 'Connecting...';
  fetch(url, {
    method: 'POST',
    headers: csrfHeaders()
  }).then(function(r) {
    if (!r.ok) throw new Error('Server returned ' + r.status);
    return r.json();
  }).then(function(data) {
    if (data.status === 'error') throw new Error(data.error || 'Tailscale did not start');
    if (!data.auth_url) {
      window.location.reload();
      return;
    }
    var signIn = document.createElement('span');
    tailscaleSignIn(signIn, data.auth_url);
    btn.replaceWith(signIn);
    waitForTailscale(statusUrl);
  }).catch(function(err) {
    alert('Failed to connect: ' + err.message);
    btn.disabled = false;
    btn.textContent = 'Connect';
  });
}

// "Sign in to Tailscale to finish", a link to its sign-in page in a new tab, and the wait for it.
function tailscaleSignIn(container, href) {
  var link = document.createElement('a');
  link.href = href;
  link.target = '_blank';
  link.rel = 'noopener';
  link.className = 'btn btn-primary btn-sm';
  link.textContent = 'Sign in to Tailscale to finish';
  var waiting = document.createElement('span');
  waiting.className = 'small text-secondary ms-2';
  waiting.textContent = 'Waiting for you to sign in…';
  container.replaceChildren(link, waiting);
}

// Asks whether Tailscale is connected every 3 seconds, for 10 minutes, and reloads once it is.
function waitForTailscale(statusUrl) {
  var tries = 0;
  var timer = setInterval(function() {
    if (++tries > 200) { clearInterval(timer); return; }
    fetch(statusUrl, { headers: { 'Accept': 'application/json' } }).then(function(r) {
      return r.ok ? r.json() : {};
    }).then(function(data) {
      if (data.running) { clearInterval(timer); window.location.reload(); }
    }).catch(function() {});
  }, 3000);
}

// Stop or log out: the button's data-args name the address.
function tailscaleAction(url) {
  fetch(url, {
    method: 'POST',
    headers: csrfHeaders()
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
    headers: csrfHeaders()
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
