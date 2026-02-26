// Theme Toggle
// Supports: 'system' (follow OS), 'dark', 'light'
// Persists to localStorage, applies data-theme attribute to <html>

(function() {
  'use strict';

  function setTheme(theme) {
    if (theme === 'system') {
      document.documentElement.removeAttribute('data-theme');
      localStorage.removeItem('theme');
    } else {
      document.documentElement.setAttribute('data-theme', theme);
      localStorage.setItem('theme', theme);
    }
    updateToggleButtons();
  }

  function currentTheme() {
    return localStorage.getItem('theme') || 'system';
  }

  function updateToggleButtons() {
    var active = currentTheme();
    document.querySelectorAll('.theme-btn').forEach(function(btn) {
      if (btn.dataset.theme === active) {
        btn.classList.add('active');
      } else {
        btn.classList.remove('active');
      }
    });
  }

  // Expose globally
  window.setTheme = setTheme;

  // Update buttons on load
  document.addEventListener('DOMContentLoaded', updateToggleButtons);
})();
