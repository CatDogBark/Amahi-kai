// Private images' form (app/views/private_images/_form): the address field only for another
// registry, GitHub's how-to only for GitHub's, and the place the token will be used for, as it's
// typed.

(function() {
  var form = document.querySelector('[data-token-form]');
  if (!form) return;

  function registry() {
    var picked = form.querySelector('[data-token-registry]:checked');
    return picked ? picked.value : 'ghcr.io';
  }

  function show() {
    var chosen = registry();
    var host = chosen === 'other' ? form.querySelector('#token-host').value.trim().toLowerCase() : chosen;
    var owner = form.querySelector('[data-token-owner]').value.trim().toLowerCase();
    form.querySelector('[data-token-other]').hidden = chosen !== 'other';
    form.querySelector('[data-token-howto]').hidden = chosen !== 'ghcr.io';
    form.querySelector('[data-token-where] code').textContent = (host || 'registry.example.com') + '/' + (owner || 'catdogbark') + '/';
  }

  form.addEventListener('input', show);
  form.addEventListener('change', show);
  show();
})();
