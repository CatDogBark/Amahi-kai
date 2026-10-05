// Apps plugin JS

// Apps (app/views/apps): the buttons post to the apps actions, then the page reloads to show the
// app's new state. Copy buttons (data-copy) copy an app's generated password or key.

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
