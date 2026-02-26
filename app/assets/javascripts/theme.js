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

  function initToggle() {
    // Remove ready class so indicator can be positioned without animation
    document.querySelectorAll('.theme-track').forEach(function(track) {
      track.classList.remove('ready');
    });
    updateToggle();
    // Re-enable animation after position is set (2 frames to be safe)
    requestAnimationFrame(function() {
      requestAnimationFrame(function() {
        document.querySelectorAll('.theme-track').forEach(function(track) {
          track.classList.add('ready');
        });
      });
    });
  }

  // 🌊 Ocean ambient toggle
  window.toggleOcean = function() {
    var off = document.documentElement.classList.toggle('ocean-off');
    localStorage.setItem('ocean-off', off ? '1' : '0');
    // Update button opacity
    document.querySelectorAll('.ocean-toggle').forEach(function(btn) {
      btn.style.opacity = off ? '0.3' : '0.6';
    });
  };

  function initOcean() {
    if (localStorage.getItem('ocean-off') === '1') {
      document.documentElement.classList.add('ocean-off');
      document.querySelectorAll('.ocean-toggle').forEach(function(btn) {
        btn.style.opacity = '0.3';
      });
    }
  }

  document.addEventListener('DOMContentLoaded', function() { initToggle(); initOcean(); });
  document.addEventListener('turbo:load', function() { initToggle(); initOcean(); });
})();
