// The setup wizard's storage step (prepare the chosen drives in a window, preview a drive)
// and its Greyhole step (install it in a window). The addresses come from the buttons'
// data-args. The window's Continue link goes to the next step.

function wizardContinueLink(href) {
  var link = document.createElement('a');
  link.href = href;
  link.className = 'btn btn-sm btn-primary';
  link.textContent = 'Continue →';
  return link;
}

function wizardTerminal(id, streamUrl, continueUrl, stepPattern) {
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
  footer.replaceChildren(wizardContinueLink(continueUrl));

  var source = new EventSource(withStreamToken(streamUrl));

  source.onmessage = function(e) {
    var line = document.createElement('div');
    line.className = 'term-line';
    var text = e.data;
    if (text.match(stepPattern)) { line.classList.add('step'); }
    else if (text.match(/✓/)) { line.classList.add('success'); }
    else if (text.match(/✗/)) { line.classList.add('error'); }
    else if (text.match(/⚠/)) { line.classList.add('warn'); }
    line.textContent = text;
    output.appendChild(line);
    terminal.scrollTop = terminal.scrollHeight;
  };

  source.addEventListener('done', function(e) {
    source.close();
    var failed = e.data === 'error';
    setTerminalState(id, failed ? 'failed' : 'done');
    setTerminalStatus(id, failed ? '✗ Finished with errors: the lines above say which' : '✓ Done', failed ? 'error' : 'success');
    cursor.style.display = 'none';
    footer.style.display = 'block';
  });

  source.onerror = function() {
    source.close();
    setTerminalState(id, 'failed');
    setTerminalStatus(id, '✗ Connection lost', 'error');
    cursor.style.display = 'none';
    footer.style.display = 'block';
    var line = document.createElement('div');
    line.className = 'term-line error';
    line.textContent = '✗ Connection lost';
    output.appendChild(line);
  };
}

// The storage form: the chosen drives are prepared in the window; none chosen goes straight on.
function prepareDrives(event, nextUrl, streamUrl) {
  event.preventDefault();
  var drives = [];
  var formatDrives = [];
  document.querySelectorAll('input[name="drives[]"]:checked').forEach(function(cb) { drives.push(cb.value); });
  document.querySelectorAll('input[name="format_drives[]"]:checked').forEach(function(cb) { formatDrives.push(cb.value); });
  if (drives.length === 0) {
    window.location.href = nextUrl;
    return;
  }
  var url = streamUrl + '?drives=' + encodeURIComponent(drives.join(',')) + '&format_drives=' + encodeURIComponent(formatDrives.join(','));
  wizardTerminal('prepare-drives', url, nextUrl, /^(Formatting|Mounting|Preparing)/);
}

function installGreyhole(streamUrl, nextUrl) {
  var copies = document.getElementById('default_copies').value;
  wizardTerminal('greyhole-install', streamUrl + '?default_copies=' + copies, nextUrl,
                 /^(Adding|Preparing|Writing|Installing|Loading|Configuring|Enabling)/);
}

function previewDrive(device, previewUrl) {
  var modal = document.getElementById('preview-modal');
  var body = document.getElementById('preview-body');
  var title = document.getElementById('preview-title');
  modal.hidden = false;
  body.innerHTML = '<div class="preview-loading"><span class="preview-spinner"></span>Reading the drive…</div>';
  title.textContent = 'Preview: ' + device;

  var token = document.querySelector('meta[name="csrf-token"]');
  fetch(previewUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': token ? token.content : '' },
    body: JSON.stringify({ device: device })
  })
  .then(function(r) { return r.json(); })
  .then(function(data) {
    if (data.status === 'error') {
      body.innerHTML = '<div class="preview-error">' + escapeHtml(data.message) + '</div>';
      return;
    }
    var html = '<div class="preview-summary">' +
      formatSize(data.total_used) + ' used · ' + data.file_count + ' file' + (data.file_count === 1 ? '' : 's') + '</div>';
    if (data.entries.length === 0) {
      html += '<div class="preview-empty">The drive is empty.</div>';
    } else {
      data.entries.forEach(function(e) {
        var icon = e.type === 'directory' ? '📁' : '📄';
        // Names come from the drive itself, so they're escaped before going into the page.
        var name = e.type === 'directory' ? '<strong>' + escapeHtml(e.name) + '</strong>' : escapeHtml(e.name);
        var info = formatSize(e.size);
        if (e.type === 'directory' && e.file_count !== undefined) info += ' · ' + e.file_count + ' files';
        html += '<div class="preview-entry"><span>' + icon + ' ' + name + '</span>' +
          '<span class="preview-size">' + info + '</span></div>';
      });
    }
    body.innerHTML = html;
  })
  .catch(function(err) {
    body.innerHTML = '<div class="preview-error">The drive couldn\'t be read: ' + escapeHtml(err.message) + '</div>';
  });
}

function closePreview() {
  document.getElementById('preview-modal').hidden = true;
}

function escapeHtml(text) {
  var div = document.createElement('div');
  div.textContent = text == null ? '' : String(text);
  return div.innerHTML;
}

function formatSize(bytes) {
  if (bytes === 0) return '0 B';
  var units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var i = Math.floor(Math.log(bytes) / Math.log(1024));
  return (bytes / Math.pow(1024, i)).toFixed(1) + ' ' + units[i];
}

document.addEventListener('DOMContentLoaded', function() {
  // The preview closes on a click beside it
  var preview = document.getElementById('preview-modal');
  if (preview) preview.addEventListener('click', function(e) { if (e.target === this) closePreview(); });
  // A drive's Format box only once the drive is chosen
  document.querySelectorAll('input[name="drives[]"]').forEach(function(driveBox) {
    driveBox.addEventListener('change', function() {
      document.querySelectorAll('[data-requires="' + this.id + '"]').forEach(function(formatBox) {
        formatBox.disabled = !driveBox.checked;
        if (!driveBox.checked) formatBox.checked = false;
      });
    });
  });
});
