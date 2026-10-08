// Forms whose button says data-confirm (button_to's data: { confirm: }) ask before they're
// sent, and a data-disable-with button shows that text while the request runs: Rails' own
// script for these isn't loaded (nor Turbo), so without this they did neither (and
// Initialize erased a drive without asking).
document.addEventListener('submit', function(event) {
  var form = event.target;
  var button = event.submitter || form.querySelector('[type=submit]');
  var message = (button && button.dataset.confirm) || form.dataset.confirm;
  if (message && !window.confirm(message)) {
    event.preventDefault();
    event.stopImmediatePropagation();
    return;
  }
  if (button && button.dataset.disableWith) {
    // After this event, so the button's own name and value are still sent.
    setTimeout(function() {
      button.disabled = true;
      button.textContent = button.dataset.disableWith;
    }, 0);
  }
}, true);

// A page waiting on something the server is doing (an element with data-reload-after, in
// seconds) reloads itself then.
document.addEventListener("DOMContentLoaded", function() {
  var waiting = document.querySelector("[data-reload-after]");
  if (waiting) {
    setTimeout(function() { window.location.reload(); }, (parseInt(waiting.dataset.reloadAfter, 10) || 30) * 1000);
  }
});

document.addEventListener("DOMContentLoaded", function() {
  // Stretch-toggle: expand/collapse settings panels
  document.addEventListener("click", function(event) {
    // Don't intercept clicks on buttons, links, inputs, or labels, or inside a <details> (its
    // <summary> opens it, which preventDefault below would stop: an app's passwords never showed)
    if (event.target.closest("a, button, input, select, textarea, label, details")) return;
    var toggle = event.target.closest(".stretchtoggle");
    if (!toggle) return;
    event.preventDefault();
    var parent = toggle.parentElement;
    var stretcher = parent ? parent.querySelector(".settings-stretcher") : null;
    if (!stretcher) {
      stretcher = toggle.nextElementSibling;
      while (stretcher && !stretcher.classList.contains("settings-stretcher")) {
        stretcher = stretcher.nextElementSibling;
      }
    }
    if (stretcher) {
      stretcher.style.display = stretcher.style.display === "none" ? "" : "none";
    }
  });

  // Open/close new entry form areas
  document.addEventListener("click", function(event) {
    var openBtn = event.target.closest(".open-area");
    if (openBtn) {
      event.preventDefault();
      var related = document.querySelector(openBtn.dataset.related);
      if (related) {
        related.style.display = related.style.display === "none" ? "" : "none";
      }
      return;
    }

    var closeBtn = event.target.closest(".close-area");
    if (closeBtn) {
      event.preventDefault();
      var target = document.querySelector(closeBtn.dataset.related);
      if (target) target.style.display = "none";
    }
  });

  // Hover highlight for focusable elements
  document.addEventListener("mouseenter", function(event) {
    if (event.target.classList && event.target.classList.contains("focus")) {
      event.target.style.backgroundColor = "rgb(255,255,153)";
    }
  }, true);

  document.addEventListener("mouseleave", function(event) {
    if (event.target.classList && event.target.classList.contains("focus")) {
      event.target.style.backgroundColor = "transparent";
    }
  }, true);

  // Search form target switching
  var webBtn = document.getElementById("websearchbutton");
  var hdaBtn = document.getElementById("hdasearchbutton");
  var searchForm = document.getElementById("searchform");

  if (webBtn && searchForm) {
    webBtn.addEventListener("click", function() { searchForm.target = "_blank"; });
  }
  if (hdaBtn && searchForm) {
    hdaBtn.addEventListener("click", function() { searchForm.target = "_self"; });
  }
});
