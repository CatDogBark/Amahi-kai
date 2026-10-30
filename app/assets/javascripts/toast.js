// Toast Notification System
//
// Global toast notifications — fixed position, no layout shift.
// Usage: showToast('Message here', 'success')
// Types: success, danger, error, warning, info, notice, failed, working

(function() {
  'use strict';

  // Map flash types to consistent Bootstrap/icon combos. Errors stay until they're dismissed: a
  // refusal says what to do first, and gone after a few seconds it was easy to miss. A failed
  // one (something broke, not something to change: flash_failure on the server) also offers
  // Report a problem, started with what went wrong. Working says a page is still waiting on the
  // server (lib/application.js); the page that comes back replaces it.
  var TYPE_MAP = {
    success: { bg: '#198754', icon: '✓', label: 'Success' },
    notice:  { bg: '#198754', icon: '✓', label: 'Success' },
    danger:  { bg: '#dc3545', icon: '✗', label: 'Error', sticky: true },
    error:   { bg: '#dc3545', icon: '✗', label: 'Error', sticky: true },
    alert:   { bg: '#dc3545', icon: '✗', label: 'Error', sticky: true },
    failed:  { bg: '#dc3545', icon: '✗', label: 'Error', sticky: true, report: true },
    warning: { bg: '#ffc107', icon: '⚠', label: 'Warning', dark: true },
    info:    { bg: '#0dcaf0', icon: 'ℹ', label: 'Info', dark: true },
    working: { bg: '#0dcaf0', icon: '…', label: 'Working', dark: true, sticky: true }
  };

  var TOAST_DURATION = 5000;
  var ANIMATION_MS = 300;
  var REPORT_URL = '/settings/help/report';

  function getContainer() {
    var container = document.getElementById('toast-container');
    if (!container) {
      container = document.createElement('div');
      container.id = 'toast-container';
      container.setAttribute('aria-live', 'polite');
      container.setAttribute('aria-atomic', 'true');
      document.body.appendChild(container);
    }
    return container;
  }

  // Report a problem, started with the flag's words and the page it came up on.
  function reportUrl(message) {
    return REPORT_URL + '?about=' + encodeURIComponent(message) +
      '&page=' + encodeURIComponent(window.location.pathname);
  }

  function showToast(message, type) {
    type = type || 'info';
    var config = TYPE_MAP[type] || TYPE_MAP.info;

    var container = getContainer();

    var toast = document.createElement('div');
    toast.className = 'amahi-toast amahi-toast-' + type;
    toast.style.cssText = 'background:' + config.bg + ';color:' + (config.dark ? '#212529' : '#fff') + ';';

    var row = document.createElement('div');
    row.className = 'amahi-toast-row';

    var icon = document.createElement('span');
    icon.className = 'amahi-toast-icon';
    icon.textContent = config.icon;

    var text = document.createElement('span');
    text.className = 'amahi-toast-text';
    text.textContent = message;

    row.appendChild(icon);
    row.appendChild(text);
    toast.appendChild(row);

    if (config.sticky) {
      // Stays until it's dismissed: by its button, never a timer.
      var actions = document.createElement('div');
      actions.className = 'amahi-toast-actions';
      var dismiss = document.createElement('button');
      dismiss.type = 'button';
      dismiss.className = 'amahi-toast-dismiss';
      dismiss.textContent = 'Dismiss';
      dismiss.onclick = function() { dismissToast(toast); };
      actions.appendChild(dismiss);
      if (config.report) {
        var report = document.createElement('a');
        report.className = 'amahi-toast-report';
        report.href = reportUrl(message);
        report.textContent = 'Report this problem';
        actions.appendChild(report);
      }
      toast.appendChild(actions);
    } else {
      var close = document.createElement('button');
      close.type = 'button';
      close.className = 'amahi-toast-close';
      close.innerHTML = '&times;';
      close.setAttribute('aria-label', 'Dismiss');
      close.style.color = config.dark ? '#212529' : '#fff';
      close.onclick = function() { dismissToast(toast); };
      row.appendChild(close);
    }

    container.appendChild(toast);

    // Trigger slide-in
    requestAnimationFrame(function() {
      requestAnimationFrame(function() {
        toast.classList.add('amahi-toast-visible');
      });
    });

    if (config.sticky) return toast; // until dismissed

    // Auto-dismiss
    var timer = setTimeout(function() { dismissToast(toast); }, TOAST_DURATION);
    toast._timer = timer;

    // Pause on hover
    toast.addEventListener('mouseenter', function() { clearTimeout(toast._timer); });
    toast.addEventListener('mouseleave', function() {
      toast._timer = setTimeout(function() { dismissToast(toast); }, 2000);
    });
    return toast;
  }

  function dismissToast(toast) {
    if (!toast || toast._dismissed) return;
    toast._dismissed = true;
    clearTimeout(toast._timer);
    toast.classList.remove('amahi-toast-visible');
    toast.classList.add('amahi-toast-leaving');
    setTimeout(function() {
      if (toast.parentNode) toast.parentNode.removeChild(toast);
    }, ANIMATION_MS);
  }

  // A flag for the page about to load: one shown now would go with the reload (the Apps page
  // reloads after Start or Stop). Kept for this tab only; without storage it shows now.
  var PENDING_KEY = 'amahi-flags-after-reload';

  function showToastAfterReload(message, type) {
    try {
      var pending = JSON.parse(window.sessionStorage.getItem(PENDING_KEY) || '[]');
      pending.push({ message: message, type: type });
      window.sessionStorage.setItem(PENDING_KEY, JSON.stringify(pending));
    } catch (e) {
      showToast(message, type);
    }
  }

  function takePending() {
    try {
      var pending = JSON.parse(window.sessionStorage.getItem(PENDING_KEY) || '[]');
      window.sessionStorage.removeItem(PENDING_KEY);
      return Array.isArray(pending) ? pending : [];
    } catch (e) {
      return [];
    }
  }

  // Expose globally
  window.showToast = showToast;
  window.dismissToast = dismissToast;
  window.showToastAfterReload = showToastAfterReload;

  // Auto-show server-rendered flash messages on DOMContentLoaded
  document.addEventListener('DOMContentLoaded', function() {
    takePending().forEach(function(m) { showToast(m.message, m.type); });
    var flashData = document.getElementById('flash-data');
    if (flashData) {
      try {
        var messages = JSON.parse(flashData.textContent);
        messages.forEach(function(m) {
          showToast(m.message, m.type);
        });
      } catch(e) {
        console.error('Failed to parse flash data:', e);
      }
      flashData.remove();
    }
  });
})();
