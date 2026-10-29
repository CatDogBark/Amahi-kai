// Forms whose button says data-confirm (button_to's data: { confirm: }) ask before they're
// sent: Rails' own script for these isn't loaded (nor Turbo), so without this they didn't (and
// Initialize erased a drive without asking).
//
// Every form sent the ordinary way, as a page load, shows it's working until the next page
// comes: its buttons are disabled, so it isn't sent twice, and the one pressed shows a spinner
// and "Working…" (or its data-disable-with). One still waiting after a few seconds also gets a
// "still working" flag. A form a script sends itself (it prevents the submit and fetches) shows
// its own; data-busy="false" on a form or button leaves it be (one that downloads a file, which
// leaves the page where it is).
var BUSY_FLAG_AFTER_MS = 5000;

document.addEventListener('submit', function(event) {
  var form = event.target;
  var button = event.submitter || form.querySelector('[type=submit]');
  var message = (button && button.dataset.confirm) || form.dataset.confirm;
  if (message && !window.confirm(message)) {
    event.preventDefault();
    event.stopImmediatePropagation();
    return;
  }
  // After this event: by then a script that sends the form itself has prevented it, and the
  // button's own name and value have been sent.
  setTimeout(function() {
    if (event.defaultPrevented) return;
    if (form.dataset.busy === 'false' || (button && button.dataset.busy === 'false')) return;
    if (form.target && form.target !== '_self') return;
    if (form.method === 'dialog') return; // closes a dialog; no page comes
    markBusy(form, button);
  }, 0);
}, true);

function markBusy(form, button) {
  form.setAttribute('aria-busy', 'true');
  var buttons = Array.prototype.slice.call(form.querySelectorAll('button, input[type=submit]'));
  if (button && buttons.indexOf(button) < 0) buttons.push(button); // one outside, with form=
  buttons.forEach(function(b) {
    if (b.disabled) return;
    b.disabled = true;
    b.dataset.busyDisabled = 'true';
  });
  if (button && button.tagName === 'BUTTON') {
    button.dataset.busyLabel = button.innerHTML;
    var spinner = document.createElement('span');
    spinner.className = 'spinner-border spinner-border-sm me-2';
    spinner.setAttribute('aria-hidden', 'true');
    button.replaceChildren(spinner, document.createTextNode(button.dataset.disableWith || 'Working…'));
  } else if (button && button.tagName === 'INPUT') {
    button.dataset.busyLabel = button.value;
    button.value = button.dataset.disableWith || 'Working…';
  }
  form._busyFlagTimer = setTimeout(function() {
    if (window.showToast) form._busyFlag = window.showToast('Still working on it: this can take a minute.', 'working');
  }, BUSY_FLAG_AFTER_MS);
}

// A page the browser brings back from its cache (Back) comes back as it was left, working:
// put its forms as they were.
window.addEventListener('pageshow', function(event) {
  if (!event.persisted) return;
  document.querySelectorAll('form[aria-busy="true"]').forEach(function(form) {
    clearTimeout(form._busyFlagTimer);
    if (window.dismissToast) window.dismissToast(form._busyFlag);
    form.removeAttribute('aria-busy');
  });
  document.querySelectorAll('[data-busy-disabled]').forEach(function(b) {
    b.disabled = false;
    delete b.dataset.busyDisabled;
  });
  document.querySelectorAll('[data-busy-label]').forEach(function(b) {
    if (b.tagName === 'INPUT') b.value = b.dataset.busyLabel;
    else b.innerHTML = b.dataset.busyLabel;
    delete b.dataset.busyLabel;
  });
});
