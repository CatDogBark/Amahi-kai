// Pool Toggle Controller
//
// Toggles a partition in/out of the Greyhole storage pool via AJAX, then reloads the page, whose
// drives, summary and status all follow the pool.

(function() {
  var PoolToggleController = class extends Stimulus.Controller {
    static get targets() { return ["checkbox", "label", "spinner"]; }
    static get values() { return { url: String, path: String }; }

    toggle() {
      var _this = this;
      var checkbox = this.checkboxTarget;
      var label = this.labelTarget;
      var spinner = this.spinnerTarget;

      checkbox.disabled = true;
      spinner.style.display = '';

      fetch(this.urlValue, {
        method: 'PUT',
        headers: csrfHeaders(),
        credentials: 'same-origin'
      })
        .then(function(response) { return response.json(); })
        .then(function(data) {
          if (data.status === 'ok') {
            label.textContent = data.checked ? 'In pool' : 'Add to pool';
            window.location.reload();
            return;
          } else {
            if (window.showToast) window.showToast(data.message || 'That didn\'t work', 'error');
            checkbox.checked = !checkbox.checked;
          }
          checkbox.disabled = false;
          spinner.style.display = 'none';
        })
        .catch(function(err) {
          console.error("Pool toggle failed:", err);
          checkbox.checked = !checkbox.checked;
          checkbox.disabled = false;
          spinner.style.display = 'none';
        });
    }
  };

  registerStimulusController("pool-toggle", PoolToggleController);
})();
