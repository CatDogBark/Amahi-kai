// Theme Toggle — 🌊 Ocean Ripple Transition
// Uses View Transition API with clip-path circle reveal + ripple rings
// Falls back to instant switch on older browsers or reduced motion

(function() {
  'use strict';

  var _transitioning = false;

  window.setTheme = function(theme, event) {
    var current = currentTheme();
    if (theme === current) return;

    var prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

    if (document.startViewTransition && event && !prefersReducedMotion && !_transitioning) {
      _transitioning = true;

      // Capture click origin as viewport percentages
      var x = (event.clientX / window.innerWidth * 100).toFixed(1) + '%';
      var y = (event.clientY / window.innerHeight * 100).toFixed(1) + '%';
      document.documentElement.style.setProperty('--ripple-x', x);
      document.documentElement.style.setProperty('--ripple-y', y);
      document.documentElement.classList.add('theme-ripple');

      // Spawn decorative ripple rings from click point
      spawnRipples(event.clientX, event.clientY);

      var transition = document.startViewTransition(function() {
        applyTheme(theme);
      });

      transition.finished.finally(function() {
        document.documentElement.classList.remove('theme-ripple');
        _transitioning = false;
      });
    } else {
      applyTheme(theme);
    }
  };

  function applyTheme(theme) {
    if (theme === 'system') {
      document.documentElement.removeAttribute('data-theme');
      localStorage.removeItem('theme');
    } else {
      document.documentElement.setAttribute('data-theme', theme);
      localStorage.setItem('theme', theme);
    }
    updateToggle();
  }

  function currentTheme() {
    return localStorage.getItem('theme') || 'system';
  }

  // Decorative ripple rings that expand from click point — like water rings
  function spawnRipples(cx, cy) {
    var count = 3;
    for (var i = 0; i < count; i++) {
      var ring = document.createElement('div');
      ring.className = 'theme-ripple-ring';
      ring.style.left = cx + 'px';
      ring.style.top = cy + 'px';
      ring.style.animationDelay = (i * 300) + 'ms';  // 300ms apart for visible spacing
      document.body.appendChild(ring);

      ring.addEventListener('animationend', function() {
        this.remove();
      });
    }
  }

  function updateToggle() {
    var active = currentTheme();

    document.querySelectorAll('.theme-track').forEach(function(track) {
      track.setAttribute('data-active', active);
    });

    document.querySelectorAll('.theme-opt').forEach(function(btn) {
      var btnTheme = btn.classList.contains('theme-opt-light') ? 'light' :
                     btn.classList.contains('theme-opt-dark') ? 'dark' : 'system';
      if (btnTheme === active) {
        btn.classList.add('active');
      } else {
        btn.classList.remove('active');
      }
    });
  }

  // Watch OS preference changes when in system mode
  window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', function() {
    if (currentTheme() === 'system') {
      applyTheme('system');
    }
  });

  document.addEventListener('DOMContentLoaded', updateToggle);
})();
