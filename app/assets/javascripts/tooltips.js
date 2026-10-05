// Tooltips. Any element with data-tip shows that text as a Bootstrap tooltip 150 ms after
// the pointer reaches it, or when it gets keyboard focus. (The browser's own title tooltip
// waits about a second, can't be styled, and nothing shows it's there.)
//
// Extra information is marked so it can be found: .tip-info adds an ⓘ (badges, status
// words), .tip-text a dotted underline (times, versions); both get the help cursor. Icon
// buttons use a plain data-tip to name themselves. data-tip-placement overrides "top".
//
// initTips(root) sets up elements added to the page later.
function initTips(root) {
  (root || document).querySelectorAll('[data-tip]').forEach(function(el) {
    bootstrap.Tooltip.getOrCreateInstance(el, {
      title: el.dataset.tip,
      placement: el.dataset.tipPlacement || 'top',
      delay: { show: 150, hide: 50 },
      container: 'body',
      trigger: 'hover focus'
    });
  });
}

document.addEventListener('DOMContentLoaded', function() { initTips(); });
