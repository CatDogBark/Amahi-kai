// The setup wizard's storage step (prepare the chosen drives in a window, preview a drive)
// and its Greyhole step (install it in a window). The addresses come from the buttons'
// data-args. The window's Continue link goes to the next step.

function wizardContinueLink(href) {
  var link = document.createElement('a');
  link.href = href;
  link.className = 'btn btn-sm btn-outline-light';
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
  wizardTerminal('greyhole-install', streamUrl + '?default_copies=' + copies, nextUrl, /^(Installing|Generating|Starting)/);
}

function previewDrive(device, previewUrl) {
  var modal = document.getElementById('preview-modal');
  var body = document.getElementById('preview-body');
  var title = document.getElementById('preview-title');
  modal.style.display = 'flex';
  body.innerHTML = '<div style="text-align:center;padding:20px;color:#7f8c9b;"><span style="display:inline-block;width:16px;height:16px;border:2px solid rgba(127,140,155,0.3);border-top-color:#7f8c9b;border-radius:50%;animation:spin 0.8s linear infinite;"></span> Reading drive…</div>';
  title.textContent = '📂 Preview: ' + device;

  var token = document.querySelector('meta[name="csrf-token"]');
  fetch(previewUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': token ? token.content : '' },
    body: JSON.stringify({ device: device })
  })
  .then(function(r) { return r.json(); })
  .then(function(data) {
    if (data.status === 'error') {
      body.innerHTML = '<div style="color:#ef4444;padding:10px;">' + escapeHtml(data.message) + '</div>';
      return;
    }
    var html = '<div style="margin-bottom:12px;font-size:13px;color:#7f8c9b;">' +
      formatSize(data.total_used) + ' used · ' + data.file_count + ' file' + (data.file_count === 1 ? '' : 's') + '</div>';
    if (data.entries.length === 0) {
      html += '<div style="color:#7f8c9b;">Drive is empty.</div>';
    } else {
      data.entries.forEach(function(e) {
        var icon = e.type === 'directory' ? '📁' : '📄';
        // Names come from the drive itself, so they're escaped before going into the page.
        var name = e.type === 'directory' ? '<strong>' + escapeHtml(e.name) + '</strong>' : escapeHtml(e.name);
        var info = formatSize(e.size);
        if (e.type === 'directory' && e.file_count !== undefined) info += ' · ' + e.file_count + ' files';
        html += '<div class="preview-entry" style="display:flex;justify-content:space-between;padding:6px 0;border-bottom:1px solid #f1f5f9;font-size:14px;">' +
          '<span>' + icon + ' ' + name + '</span>' +
          '<span class="preview-size" style="color:#7f8c9b;font-size:13px;">' + info + '</span></div>';
      });
    }
    body.innerHTML = html;
  })
  .catch(function(err) {
    body.innerHTML = '<div style="color:#ef4444;padding:10px;">Failed to preview drive: ' + escapeHtml(err.message) + '</div>';
  });
}

function closePreview() {
  document.getElementById('preview-modal').style.display = 'none';
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
