// Theme Toggle
// Supports: 'system' (follow OS), 'dark', 'light'
// Persists to localStorage, applies data-theme attribute to <html>

(function() {
  'use strict';

  window.setTheme = function(theme) {
    if (theme === 'system') {
      document.documentElement.removeAttribute('data-theme');
      localStorage.removeItem('theme');
    } else {
      document.documentElement.setAttribute('data-theme', theme);
      localStorage.setItem('theme', theme);
    }
    updateToggle();
  };

  function currentTheme() {
    return localStorage.getItem('theme') || 'system';
  }

  function updateToggle() {
    var active = currentTheme();

    // Update track data attribute for indicator position
    document.querySelectorAll('.theme-track').forEach(function(track) {
      track.setAttribute('data-active', active);
    });

    // Update active class on buttons
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

  // Update on load
  document.addEventListener('DOMContentLoaded', updateToggle);
})();
