// Create Form Controller
//
// Handles form submission with loading indicator.
// Shows spinner on submit button, disables form, reloads on success.

(function() {
  var CreateFormController = class extends Stimulus.Controller {
    static get values() { return { target: String }; }

    submit(event) {
      var form = this.element;
      var submitBtn = form.querySelector('[type="submit"]');
      var spinner = form.querySelector('.spinner');

      // Show loading state
      if (submitBtn) {
        submitBtn.disabled = true;
        submitBtn.dataset.originalText = submitBtn.textContent;
        submitBtn.innerHTML = '<span class="spinner-border spinner-border-sm me-1"></span> Creating...';
      }
      if (spinner) spinner.style.display = '';

      // Let the form submit normally (no preventDefault) — the server redirects back
    }
  };

  registerStimulusController("create-form", CreateFormController);
})();
