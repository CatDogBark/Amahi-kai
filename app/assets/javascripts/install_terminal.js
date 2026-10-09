// The streaming install window (shared/install_terminal): one per job on a page, opened by
// openInstallTerminal(id[, url]) from a button's data-call, following the job's stream; System
// Update's own start and follow (startSystemUpdate), and the page's reload when it's closed.

function terminalLineClass(text) {
  if (text.match(/^(Adding|Updating|Installing|Setting up|Enabling|Starting|Generating|Configuring|Pre-configuring|Creating|Loading|Downloading|Backing up|Running|Pulling|Restarting|Precompiling)/)) return 'step';
  if (text.match(/^✓/)) return 'success';
  if (text.match(/^✗/)) return 'error';
  if (text.match(/^⚠/)) return 'warn';
  return '';
}

// Follows the output, unless the reader has scrolled up to look at something.
function appendTerminalLine(id, text, cls) {
  var output = document.getElementById(id + '-output');
  var terminal = document.getElementById(id + '-terminal');
  var atBottom = terminal.scrollHeight - terminal.scrollTop - terminal.clientHeight < 40;
  var line = document.createElement('div');
  line.className = 'term-line';
  cls = cls || terminalLineClass(text);
  if (cls) line.classList.add(cls);
  line.textContent = text;
  output.appendChild(line);
  if (atBottom) terminal.scrollTop = terminal.scrollHeight;
}

// --- The status bar: what's happening, for how long, and how it ended ---

var terminalClocks = {};

function formatElapsed(ms) {
  var s = Math.max(0, Math.round(ms / 1000));
  return Math.floor(s / 60) + ':' + ('0' + (s % 60)).slice(-2);
}

function setTerminalStatus(id, text, cls) {
  var el = document.getElementById(id + '-status');
  if (!el) return;
  el.textContent = text;
  el.className = 'term-status' + (cls ? ' ' + cls : '');
}

function startTerminalClock(id, label) {
  stopTerminalClock(id);
  var clock = { started: Date.now(), label: label };
  clock.tick = function() { setTerminalStatus(id, clock.label + ' ' + formatElapsed(Date.now() - clock.started)); };
  clock.timer = setInterval(clock.tick, 1000);
  terminalClocks[id] = clock;
  clock.tick();
}

function setTerminalClockLabel(id, label) {
  var clock = terminalClocks[id];
  if (!clock || clock.label === label) return;
  clock.label = label;
  clock.tick();
}

// Elapsed milliseconds since the clock started, or null.
function stopTerminalClock(id) {
  var clock = terminalClocks[id];
  if (!clock) return null;
  clearInterval(clock.timer);
  delete terminalClocks[id];
  return Date.now() - clock.started;
}

function terminalButton(id) {
  return document.querySelector('#' + id + '-install-footer button');
}

// Ends a run: the cursor stops, the status says how it went, the button appears.
function finishTerminal(id, cls, message, buttonLabel) {
  var took = stopTerminalClock(id);
  document.getElementById(id + '-cursor').style.display = 'none';
  if (message) setTerminalStatus(id, message + (took === null ? '' : ' in ' + formatElapsed(took)), cls);
  var button = terminalButton(id);
  if (button && buttonLabel) button.textContent = buttonLabel;
  document.getElementById(id + '-install-footer').style.display = 'block';
  if (button) button.focus();
}

function resetTerminal(id) {
  document.getElementById(id + '-install-modal').style.display = 'flex';
  document.getElementById(id + '-output').innerHTML = '';
  document.getElementById(id + '-cursor').style.display = '';
  document.getElementById(id + '-install-footer').style.display = 'none';
  var button = terminalButton(id);
  if (button) {
    button.textContent = 'Close & Refresh';
    delete button.dataset.waitForServer;
  }
  setTerminalStatus(id, '');
}

// --- System Update ---

// System Update runs as its own job on the NAS. Start it, then follow its log; the app
// restarts during the update, so the log stream is reopened from where it left off.
function startSystemUpdate(id, startUrl, streamUrl) {
  resetTerminal(id);
  startTerminalClock(id, 'Updating…');
  appendTerminalLine(id, 'Starting system update...');

  var token = document.querySelector('meta[name=csrf-token]');
  fetch(startUrl, {
    method: 'POST', credentials: 'same-origin',
    headers: { 'X-CSRF-Token': token ? token.content : '', 'Accept': 'application/json' }
  }).then(function(r) {
    return r.json().catch(function() { return {}; }).then(function(data) {
      if (!r.ok || data.status !== 'ok') throw new Error(data.error || ('HTTP ' + r.status));
      followSystemUpdate(id, streamUrl, 0, 0);
    });
  }).catch(function(err) {
    appendTerminalLine(id, '✗ System Update didn\'t start: ' + err.message);
    finishTerminal(id, 'error', '✗ System Update didn\'t start', 'Close & Refresh');
  });
}

var terminalLastLines = {};

function followSystemUpdate(id, url, from, retries) {
  var received = from;
  var source = new EventSource(withStreamToken(url + (url.indexOf('?') === -1 ? '?' : '&') + 'from=' + from));
  source.onmessage = function(e) {
    received++;
    retries = 0;
    terminalLastLines[id] = e.data;
    setTerminalClockLabel(id, 'Updating…');
    appendTerminalLine(id, e.data);
  };
  // "done" comes from the restarted app, so it's already answering: reloading is all
  // that's left (the page then loads the new version's scripts and styles).
  source.addEventListener('done', function(e) {
    source.close();
    if (e.data === 'success') {
      var current = (terminalLastLines[id] || '').indexOf('Already up to date') !== -1;
      finishTerminal(id, 'success', current ? '✓ Already up to date' : '✓ Updated', 'Reload page');
    } else {
      finishTerminal(id, 'error', '✗ The update didn\'t finish; the log above says why', 'Reload page');
    }
  });
  source.onerror = function() {
    source.close();
    if (retries === 0) {
      appendTerminalLine(id, '… Waiting for Amahi-kai to restart', 'warn');
      setTerminalClockLabel(id, 'Restarting Amahi-kai…');
    }
    if (retries >= 90) {
      appendTerminalLine(id, '⚠ Lost track of the update. It keeps running on the NAS; refresh this page in a minute.');
      finishTerminal(id, 'warn', '⚠ Lost track of the update', 'Reload page');
      var button = terminalButton(id);
      if (button) button.dataset.waitForServer = 'true';
      return;
    }
    setTimeout(function() { followSystemUpdate(id, url, received, retries + 1); }, 2000);
  };
}

// Reloads once Amahi-kai answers again. Any reply short of an error page counts; through
// the Cloudflare Tunnel a stopped app comes back as a 502 or 530, which is a miss too.
function waitForServer(id) {
  document.getElementById(id + '-install-footer').style.display = 'none';
  startTerminalClock(id, 'Waiting for Amahi-kai…');
  var attempts = 0;
  var check = function() {
    attempts++;
    fetch(window.location.origin + '/login', { method: 'HEAD', cache: 'no-store' })
      .then(function(resp) { return resp.status < 500; })
      .catch(function() { return false; })
      .then(function(up) {
        if (up) {
          stopTerminalClock(id);
          setTerminalStatus(id, '✓ Amahi-kai is back. Reloading…', 'success');
          setTimeout(function() { window.location.reload(); }, 800);
        } else if (attempts >= 45) {
          finishTerminal(id, 'warn', '⚠ Amahi-kai isn\'t answering yet. Try again in a minute', 'Try again');
        } else {
          setTimeout(check, 2000);
        }
      });
  };
  check();
}

// --- Other installs ---

function openInstallTerminal(id, url) {
  if (typeof url === 'undefined') url = document.getElementById(id + '-install-modal').dataset.streamUrl;
  resetTerminal(id);
  startTerminalClock(id, 'Running…');

  var source = new EventSource(withStreamToken(url));

  source.onmessage = function(e) {
    appendTerminalLine(id, e.data);
  };

  source.addEventListener('done', function(e) {
    source.close();
    if (e.data === 'error') {
      finishTerminal(id, 'error', '✗ Finished with errors');
    } else {
      finishTerminal(id, 'success', '✓ Done');
    }
  });

  source.onerror = function() {
    source.close();
    appendTerminalLine(id, '✗ Connection lost', 'error');
    finishTerminal(id, 'error', '✗ Connection lost');
  };
}

function closeInstallTerminal(id) {
  var button = terminalButton(id);
  if (button && button.dataset.waitForServer === 'true') {
    waitForServer(id);
    return;
  }
  document.getElementById(id + '-install-modal').style.display = 'none';
  window.location.reload();
}
