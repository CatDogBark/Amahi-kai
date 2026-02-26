// Toast Notification System
//
// Global toast notifications — fixed position, no layout shift.
// Usage: showToast('Message here', 'success')
// Types: success, danger, error, warning, info, notice

(function() {
  'use strict';

  // Map flash types to consistent Bootstrap/icon combos
  var TYPE_MAP = {
    success: { bg: '#198754', icon: '✓', label: 'Success' },
    notice:  { bg: '#198754', icon: '✓', label: 'Success' },
    danger:  { bg: '#dc3545', icon: '✗', label: 'Error' },
    error:   { bg: '#dc3545', icon: '✗', label: 'Error' },
    warning: { bg: '#ffc107', icon: '⚠', label: 'Warning', dark: true },
    info:    { bg: '#0dcaf0', icon: 'ℹ', label: 'Info', dark: true },
    alert:   { bg: '#dc3545', icon: '✗', label: 'Error' }
  };

  var TOAST_DURATION = 5000;
  var ANIMATION_MS = 300;

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

  function showToast(message, type) {
    type = type || 'info';
    var config = TYPE_MAP[type] || TYPE_MAP.info;

    var container = getContainer();

    var toast = document.createElement('div');
    toast.className = 'amahi-toast';
    toast.style.cssText = 'background:' + config.bg + ';color:' + (config.dark ? '#212529' : '#fff') + ';';

    var icon = document.createElement('span');
    icon.className = 'amahi-toast-icon';
    icon.textContent = config.icon;

    var text = document.createElement('span');
    text.className = 'amahi-toast-text';
    text.textContent = message;

    var close = document.createElement('button');
    close.className = 'amahi-toast-close';
    close.innerHTML = '&times;';
    close.setAttribute('aria-label', 'Dismiss');
    close.style.color = config.dark ? '#212529' : '#fff';
    close.onclick = function() { dismissToast(toast); };

    toast.appendChild(icon);
    toast.appendChild(text);
    toast.appendChild(close);

    container.appendChild(toast);

    // Trigger slide-in
    requestAnimationFrame(function() {
      requestAnimationFrame(function() {
        toast.classList.add('amahi-toast-visible');
      });
    });

    // Auto-dismiss
    var timer = setTimeout(function() { dismissToast(toast); }, TOAST_DURATION);
    toast._timer = timer;

    // Pause on hover
    toast.addEventListener('mouseenter', function() { clearTimeout(toast._timer); });
    toast.addEventListener('mouseleave', function() {
      toast._timer = setTimeout(function() { dismissToast(toast); }, 2000);
    });
  }

  function dismissToast(toast) {
    if (toast._dismissed) return;
    toast._dismissed = true;
    clearTimeout(toast._timer);
    toast.classList.remove('amahi-toast-visible');
    toast.classList.add('amahi-toast-leaving');
    setTimeout(function() {
      if (toast.parentNode) toast.parentNode.removeChild(toast);
    }, ANIMATION_MS);
  }

  // Expose globally
  window.showToast = showToast;

  // Auto-show server-rendered flash messages on DOMContentLoaded
  document.addEventListener('DOMContentLoaded', function() {
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
