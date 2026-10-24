// Network → Devices, This NAS: the page shown while the NAS moves to another address on the
// interface this browser reached it through. It tries the NAS at the new address until it
// answers (a request arriving there is what keeps the change), then goes there. When nothing
// answers within the time the helper waits, the NAS has gone back to the old address, and the
// page goes back too. The old address may still answer through another interface, so where the
// change stands is asked there as well.
(function() {
  document.addEventListener('DOMContentLoaded', function() {
    var page = document.getElementById('address-move');
    if (!page) return;
    var until = Number(page.dataset.until) * 1000;
    var state = page.querySelector('.address-move-state');
    var countdown = page.querySelector('.address-move-countdown');
    var done = false;

    function go(url) {
      done = true;
      countdown.textContent = '';
      setTimeout(function() { window.location.href = url; }, 1500);
    }

    function reached() {
      if (done) return;
      state.textContent = 'The NAS answers at ' + page.dataset.new + '. Going there…';
      go(page.dataset.target);
    }

    function back(why) {
      if (done) return;
      state.textContent = why + ' Going back to ' + page.dataset.old + '…';
      go(page.dataset.back);
    }

    // Any answer from the new address will do (the response is opaque across origins).
    function probe() {
      var controller = new AbortController();
      setTimeout(function() { controller.abort(); }, 3000);
      fetch(page.dataset.probe, { method: 'POST', mode: 'no-cors', cache: 'no-store', signal: controller.signal })
        .then(reached, function() {});
    }

    function status() {
      fetch(page.dataset.status, { headers: { Accept: 'application/json' }, cache: 'no-store' })
        .then(function(response) { return response.ok ? response.json() : null; })
        .then(function(change) {
          if (!change) return;
          if (change.state === 'kept') reached();
          else if (change.state === 'reverted') back('Nothing reached the NAS at ' + page.dataset.new + ', so it went back.');
        }, function() {});
    }

    var timer = setInterval(function() {
      if (done) { clearInterval(timer); return; }
      var left = Math.round((until - Date.now()) / 1000);
      if (left > 0) countdown.textContent = '(' + left + ' s left)';
      else if (left < -20) back('Nothing reached the NAS at ' + page.dataset.new + ' in time, so it has gone back.');
      probe();
      status();
    }, 3000);
  });
})();
