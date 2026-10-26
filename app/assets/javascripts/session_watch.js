// A page whose sign-in ended goes to the sign-in page, and comes back to itself after it,
// instead of its buttons failing with "no answer from Amahi-kai".
//
// Amahi-kai says so on any request a page makes by itself (the X-Amahi-Session header, from
// ApplicationController#tell_page): "signed-out" when the sign-in ended (the idle limit, a
// sign-out elsewhere, a reinstall), "out-of-date" when the page's token is from an earlier one.
// Either way the page reloads: signed out, that leads to the sign-in page; out of date, to the
// same page, fresh, with a word on why. The request's own handler never sees the answer.
//
// A signed-in page also asks, without that counting as use, once its sign-in is due to end (the
// amahi-session meta tag), and whenever it's looked at again after being away (a tab in the
// background, a laptop asleep), so it goes to the sign-in page by itself.
(function() {
  var NOTICE = 'amahi-session-notice';
  var LAST_RELOAD = 'amahi-session-reloaded';
  var reloading = false;

  function stored(key, value) {
    try {
      if (value === undefined) return sessionStorage.getItem(key);
      if (value === null) sessionStorage.removeItem(key); else sessionStorage.setItem(key, value);
    } catch (e) { return null; } // storage blocked: no notice, no guard against a reload loop
    return null;
  }

  // Reloads for the page's state, unless it reloaded for it moments ago: a page that keeps
  // being told so (cookies blocked, say) shows its request's own error instead of reloading on.
  function reloadFor(state) {
    if (reloading) return true;
    var last = Number(stored(LAST_RELOAD)) || 0;
    if (Date.now() - last < 30000) return false;
    stored(LAST_RELOAD, String(Date.now()));
    if (state === 'out-of-date') stored(NOTICE, 'This page was out of date, so it was reloaded. Try again.');
    reloading = true;
    window.location.reload();
    return true;
  }

  var originalFetch = window.fetch;
  if (originalFetch) {
    window.fetch = function() {
      return originalFetch.apply(this, arguments).then(function(response) {
        var state = response.headers.get('X-Amahi-Session');
        if ((state === 'signed-out' || state === 'out-of-date') && reloadFor(state)) {
          return new Promise(function() {}); // the page is going: its handler waits for nothing
        }
        return response;
      });
    };
  }

  function watch() {
    var meta = document.querySelector('meta[name="amahi-session"]');
    if (!meta) return;
    var timer = null;
    var lastCheck = 0;

    function schedule(seconds) {
      clearTimeout(timer);
      // A day at most: a remembered sign-in lasts a week, past what a timer can wait
      timer = setTimeout(check, Math.min(Math.max(seconds, 0) + 2, 86400) * 1000);
    }

    function check() {
      lastCheck = Date.now();
      fetch(meta.content, { headers: { Accept: 'application/json' }, cache: 'no-store', credentials: 'same-origin' })
        .then(function(r) { return r.json(); })
        .then(function(data) { if (data.status === 'ok') schedule(data.ends_in); })
        .catch(function() { schedule(60); }); // no answer (Amahi-kai restarting): again in a minute
    }

    function lookedAt() {
      if (document.visibilityState === 'visible' && Date.now() - lastCheck > 30000) check();
    }

    schedule(Number(meta.dataset.endsIn) || 0);
    document.addEventListener('visibilitychange', lookedAt);
    window.addEventListener('focus', lookedAt);
  }

  document.addEventListener('DOMContentLoaded', function() {
    var notice = stored(NOTICE);
    if (notice) {
      stored(NOTICE, null);
      if (window.showToast) window.showToast(notice, 'notice');
    }
    watch();
  });
})();
