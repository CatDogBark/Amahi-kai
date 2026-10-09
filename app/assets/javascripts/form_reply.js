// A page that answers a form (drawn again with the form's errors, so its body has
// data-form-reply) replaces its history entry with the same address. Reloading it then asks for
// the page again instead of sending the form a second time (Firefox's "resend" question), whoever
// reloads it: the browser, System Update's Reload page, or a page that reloads itself while it
// waits. Every layout loads it: application.js and setup.js require it, the sign-in page includes it.
(function() {
  function settle() {
    if (document.body && document.body.hasAttribute('data-form-reply') && window.history.replaceState) {
      window.history.replaceState(window.history.state, '', window.location.href);
    }
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', settle);
  else settle();
})();
