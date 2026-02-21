// Pool Toggle Controller
//
// Toggles a partition in/out of the Greyhole storage pool via AJAX.

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
        .then(function(response) { return response.text(); })
        .then(function(html) {
          // Parse the response to get the new checked state
          var temp = document.createElement('div');
          temp.innerHTML = html;
          var newCheckbox = temp.querySelector('input[type="checkbox"]');
          var isChecked = newCheckbox && newCheckbox.hasAttribute('checked');

          checkbox.checked = isChecked;
          label.textContent = isChecked ? 'In pool' : 'Add to pool';
          checkbox.disabled = false;
          spinner.style.display = 'none';
        })
        .catch(function(err) {
          console.error("Pool toggle failed:", err);
          // Revert checkbox
          checkbox.checked = !checkbox.checked;
          checkbox.disabled = false;
          spinner.style.display = 'none';
        });
    }
  };

  registerStimulusController("pool-toggle", PoolToggleController);
})();
