// Settings → Help's logs: a tab per log. Amahi-kai's own is in the page; the others are fetched
// from help_log the first time their tab is opened, and kept for when it's opened again.
document.addEventListener('DOMContentLoaded', function() {
  var log = document.getElementById('help-log');
  if (!log) return;
  var about = document.getElementById('help-log-about');
  var tabs = Array.prototype.slice.call(document.querySelectorAll('[data-log-source]'));
  var loaded = {};
  if (tabs.length) loaded[tabs[0].dataset.logSource] = log.textContent;
  var current = tabs.length ? tabs[0].dataset.logSource : null;

  function show(tab) {
    var key = tab.dataset.logSource;
    current = key;
    tabs.forEach(function(t) { t.setAttribute('aria-selected', t === tab ? 'true' : 'false'); });
    about.textContent = tab.dataset.logAbout;
    if (loaded[key] !== undefined) {
      log.textContent = loaded[key];
      return;
    }
    log.textContent = 'Reading…';
    log.setAttribute('aria-busy', 'true');
    fetch(log.dataset.logUrl + '?source=' + encodeURIComponent(key), { credentials: 'same-origin', headers: { Accept: 'application/json' } })
      .then(function(r) { return r.json().catch(function() { return { error: 'No answer from Amahi-kai' }; }); })
      .then(function(data) {
        var text = data.error ? data.error : (data.lines || []).join('\n') || '(empty)';
        if (!data.error) loaded[key] = text;
        if (current === key) log.textContent = text;
      })
      .catch(function(err) { if (current === key) log.textContent = "Couldn't read it: " + err.message; })
      .then(function() { log.removeAttribute('aria-busy'); });
  }

  tabs.forEach(function(tab) {
    tab.addEventListener('click', function() { show(tab); });
  });
});
