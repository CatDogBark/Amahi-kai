// Delete Controller
//
// Sends a DELETE request, removes the target element on success.
//
// Usage:
//   div[data-controller="delete"]
//     button[data-action="click->delete#destroy"]
//       [data-delete-url-value="/resource/123"]
//     span.spinner[data-delete-target="spinner" style="display:none"]
//
// Optional:
//   data-delete-confirm-value="Are you sure?" — confirm dialog
//   data-delete-remove-selector-value="#element_123" — element to remove (default: controller element)

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
      if (this.hasSpinnerTarget) this.spinnerTarget.style.display = "";

      var csrfToken = document.querySelector('meta[name="csrf-token"]');
      var headers = {
        "Accept": "application/json",
        "X-Requested-With": "XMLHttpRequest"
      };
      if (csrfToken) headers["X-CSRF-Token"] = csrfToken.content;

      fetch(url, { method: "DELETE", headers: headers, credentials: "same-origin" })
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
            _this.dispatch("success", { detail: data });
          } else {
            if (_this.hasSpinnerTarget) _this.spinnerTarget.style.display = "none";
            alert(data.status || "Error");
          }
        })
        .catch(function(err) {
          console.error("Delete failed:", err);
          if (_this.hasSpinnerTarget) _this.spinnerTarget.style.display = "none";
        });
    }
  };

  registerStimulusController("delete", DeleteController);
})();
