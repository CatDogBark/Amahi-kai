// Network → Security, and Remote Access's audit: runs the security audit in its window,
// offering Fix All Issues when something can be fixed, and fixes one check from its row.
// The addresses come from the buttons' data-args.

function terminalCloseButton(id) {
  var button = document.createElement('button');
  button.type = 'button';
  button.className = 'btn btn-sm btn-outline-light';
  button.textContent = 'Close & Refresh';
  button.dataset.call = 'closeInstallTerminal';
  button.dataset.args = JSON.stringify([id]);
  return button;
}

function runSecurityAudit(auditUrl, fixUrl) {
  var id = 'security-audit';
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

  var source = new EventSource(withStreamToken(auditUrl));

  source.onmessage = function(e) {
    var line = document.createElement('div');
    line.className = 'term-line';
    var text = e.data;
    if (text.match(/^(Checking|Running)/)) { line.classList.add('step'); }
    else if (text.match(/^  ✓/)) { line.classList.add('success'); }
    else if (text.match(/^  ✗/) || text.match(/^✗/)) { line.classList.add('error'); }
    else if (text.match(/^  ⚠/) || text.match(/^⚠/)) { line.classList.add('warn'); }
    else if (text.match(/^───/)) { line.style.color = '#7f8c9b'; line.style.fontWeight = 'bold'; line.style.marginTop = '8px'; }
    line.textContent = text;
    output.appendChild(line);
    terminal.scrollTop = terminal.scrollHeight;
  };

  source.addEventListener('has_fixable', function(e) {
    if (e.data !== 'true') return;
    var fixBtn = document.createElement('button');
    fixBtn.type = 'button';
    fixBtn.className = 'btn btn-sm btn-warning me-2';
    fixBtn.textContent = 'Fix All Issues';
    fixBtn.addEventListener('click', function() {
      // The audit's window goes without a reload (closeInstallTerminal reloads)
      modal.style.display = 'none';
      openInstallTerminal('security-fix', fixUrl);
    });
    footer.insertBefore(fixBtn, footer.firstChild);
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
    var line = document.createElement('div');
    line.className = 'term-line error';
    line.textContent = '✗ Connection lost';
    output.appendChild(line);
  };
}

function fixCheck(name, btn, fixUrl) {
  btn.disabled = true;
  btn.innerHTML = '<span class="spinner-border spinner-border-sm" role="status"></span>';
  fetch(fixUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': document.querySelector('meta[name=csrf-token]').content },
    body: JSON.stringify({ check_name: name })
  }).then(function(r) { return r.json(); }).then(function(data) {
    if (data.status === 'ok') {
      window.location.reload();
    } else {
      alert('Fix failed for: ' + name + (data.error ? '\n\n' + data.error : ''));
      btn.disabled = false;
      btn.textContent = 'Fix';
    }
  }).catch(function() {
    btn.disabled = false;
    btn.textContent = 'Fix';
  });
}
