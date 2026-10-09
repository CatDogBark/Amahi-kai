// What a button, link, form or input does, said in its markup instead of an inline handler
// (which a Content-Security-Policy refuses):
//
//   data-call="functionName"          the page function to call (click; change for a select
//                                     or input; submit for a form)
//   data-args='["a", 3, "@el"]'       its arguments as JSON; "@el" is the element itself,
//                                     "@event" the event
//   data-confirm="Really?"            asked first
//
// A link or form with data-call doesn't also follow or submit. Also:
//   data-autosubmit                   a select or input that submits its form on change
//   data-fallback (on an img)         when it fails to load, it's hidden and the next element
//                                     with data-fallback-for is shown
//   data-reveal=".selector"           a link that shows or hides the element matching the
//                                     selector in its parent
//   data-reveal-hide=".selector"      a link that hides the closest such element and clears
//                                     its password fields
(function() {
  function callOf(el, event) {
    var fn = window[el.dataset.call];
    if (typeof fn !== 'function') {
      console.error('data-call: no function named', el.dataset.call);
      return;
    }
    var args = el.dataset.args ? JSON.parse(el.dataset.args) : [];
    args = args.map(function(arg) { return arg === '@el' ? el : arg === '@event' ? event : arg; });
    fn.apply(el, args);
  }

  function run(el, event) {
    if (el.tagName === 'A' || el.tagName === 'FORM') event.preventDefault();
    if (el.dataset.confirm && !window.confirm(el.dataset.confirm)) return;
    callOf(el, event);
  }

  document.addEventListener('click', function(event) {
    var el = event.target.closest('[data-call]');
    if (el && !['FORM', 'SELECT', 'INPUT'].includes(el.tagName)) run(el, event);
    var reveal = event.target.closest('[data-reveal]');
    if (reveal) {
      event.preventDefault();
      var target = reveal.parentElement.querySelector(reveal.dataset.reveal);
      if (target) target.style.display = target.style.display === 'none' ? '' : 'none';
    }
    var hide = event.target.closest('[data-reveal-hide]');
    if (hide) {
      event.preventDefault();
      var box = hide.closest(hide.dataset.revealHide);
      if (box) {
        box.style.display = 'none';
        box.querySelectorAll('input[type=password]').forEach(function(input) { input.value = ''; });
      }
    }
  });

  document.addEventListener('change', function(event) {
    var el = event.target;
    if (el.matches('select[data-call], input[data-call]')) run(el, event);
    if (el.matches('[data-autosubmit]') && el.form) el.form.requestSubmit();
  });

  document.addEventListener('submit', function(event) {
    var form = event.target;
    if (form.matches('form[data-call]')) run(form, event);
  });

  // Error events don't bubble, so this listens in the capture phase.
  document.addEventListener('error', function(event) {
    var img = event.target;
    if (!(img instanceof HTMLImageElement) || !img.hasAttribute('data-fallback')) return;
    img.hidden = true;
    var fallback = img.nextElementSibling;
    if (fallback && fallback.hasAttribute('data-fallback-for')) fallback.classList.remove('d-none');
  }, true);
})();
