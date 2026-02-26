// Delete Controller
//
// Sends a DELETE request, removes the target element on success.
// Shows spinner on the triggering button during request.

(function() {
  var DeleteController = class extends Stimulus.Controller {
    static get targets() { return ["spinner"]; }
    static get values() { return { url: String, confirm: String, removeSelector: String }; }

    destroy(event) {
      event.preventDefault();
      var _this = this;

      if (this.hasConfirmValue && this.confirmValue) {
        if (!confirm(this.confirmValue)) return;
      }

      var url = this.urlValue;
      var btn = event.currentTarget;

      // Show loading state on button (match create style)
      if (btn) {
        btn.dataset.originalText = btn.textContent;
        btn.innerHTML = '<span class="spinner-border spinner-border-sm me-1"></span> Deleting...';
        btn.style.pointerEvents = 'none';
      }

      fetch(url, { method: "DELETE", headers: csrfHeaders(), credentials: "same-origin" })
        .then(function(response) { return response.json(); })
        .then(function(data) {
          if (data.status === "ok") {
            var target;
            if (_this.hasRemoveSelectorValue) {
              target = document.querySelector(_this.removeSelectorValue);
            } else {
              target = _this.element;
            }
            if (target) {
              target.style.transition = "opacity 0.5s";
              target.style.opacity = "0";
              setTimeout(function() { target.remove(); }, 500);
            }
            if (typeof showToast === 'function') showToast('Deleted successfully', 'success');
            _this.dispatch("success", { detail: data });
          } else {
            // Restore button
            if (btn) {
              btn.innerHTML = btn.dataset.originalText;
              btn.style.pointerEvents = '';
            }
            if (typeof showToast === 'function') showToast(data.status || "Error", 'error');
          }
        })
        .catch(function(err) {
          console.error("Delete failed:", err);
          if (btn) {
            btn.innerHTML = btn.dataset.originalText;
            btn.style.pointerEvents = '';
          }
        });
    }
  };

  registerStimulusController("delete", DeleteController);
})();
