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
      // The button's own nodes, put back as they were: its text names the share, so it's never
      // read back in as HTML.
      var original = btn ? Array.from(btn.childNodes) : [];
      var restore = function() {
        if (!btn) return;
        btn.replaceChildren.apply(btn, original);
        btn.style.pointerEvents = '';
      };

      // Show loading state on button (match create style)
      if (btn) {
        var spinner = document.createElement('span');
        spinner.className = 'spinner-border spinner-border-sm me-1';
        btn.replaceChildren(spinner, ' Deleting...');
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
            restore();
            // The server's reason when it gives one (a share with files on the pool drives)
            if (typeof showToast === 'function') showToast(data.message || data.status || "Error", 'error');
          }
        })
        .catch(function(err) {
          console.error("Delete failed:", err);
          restore();
        });
    }
  };

  registerStimulusController("delete", DeleteController);
})();
