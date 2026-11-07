// Add your own app (app/views/custom_apps/new): the form's two tabs (Describe it, I have an app
// file), its rows (ports, folders, settings, secrets) added from the page's templates and
// removed, the kernel permissions shown only for an app that runs as the image says, and a
// setting's value only when it's one you type.

(function() {
  var form = document.querySelector('[data-custom-form]');
  if (!form) return;
  var made = 0;

  function showTab(name) {
    form.querySelector('[data-custom-source]').value = name;
    form.querySelectorAll('[data-custom-tab]').forEach(function(tab) {
      tab.setAttribute('aria-selected', String(tab.dataset.customTab === name));
    });
    form.querySelectorAll('[data-custom-panel]').forEach(function(panel) {
      panel.hidden = panel.dataset.customPanel !== name;
    });
  }

  function showCapabilities() {
    var picked = form.querySelector('[data-custom-runs]:checked');
    form.querySelector('[data-custom-caps]').hidden = !picked || picked.value !== 'image';
  }

  function showValue(select) {
    var value = select.closest('[data-custom-row]').querySelector('[data-custom-value]');
    if (value) value.hidden = select.value !== 'value';
  }

  form.addEventListener('click', function(event) {
    var tab = event.target.closest('[data-custom-tab]');
    if (tab) {
      showTab(tab.dataset.customTab);
      return;
    }
    var add = event.target.closest('[data-custom-add]');
    if (add) {
      var kind = add.dataset.customAdd;
      var template = document.querySelector('[data-custom-template="' + kind + '"]');
      made += 1;
      var key = 'new' + Date.now() + made;
      var holder = document.createElement('div');
      holder.innerHTML = template.innerHTML.split('__KEY__').join(key);
      var row = holder.firstElementChild;
      form.querySelector('[data-custom-rows="' + kind + '"]').appendChild(row);
      var first = row.querySelector('input');
      if (first) first.focus();
      return;
    }
    var remove = event.target.closest('[data-custom-remove]');
    if (remove) remove.closest('[data-custom-row]').remove();
  });

  form.addEventListener('change', function(event) {
    if (event.target.matches('[data-custom-runs]')) showCapabilities();
    if (event.target.matches('[data-custom-kind]')) showValue(event.target);
  });

  // The tabs as tabs: arrow keys move between them
  form.querySelector('[role="tablist"]').addEventListener('keydown', function(event) {
    if (event.key !== 'ArrowRight' && event.key !== 'ArrowLeft') return;
    var tabs = Array.prototype.slice.call(form.querySelectorAll('[data-custom-tab]'));
    var next = tabs[(tabs.indexOf(document.activeElement) + 1) % tabs.length];
    next.focus();
    showTab(next.dataset.customTab);
  });
})();
