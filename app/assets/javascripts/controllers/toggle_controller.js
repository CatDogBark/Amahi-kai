// Toggle Controller
//
// Replaces RemoteCheckbox pattern: sends a PUT request to toggle a boolean,
// updates the UI based on the response.
//
// Usage:
//   div[data-controller="toggle"]
//     input[type="checkbox"][data-toggle-target="checkbox"]
//       [data-action="click->toggle#toggle"]
//       [data-toggle-url-value="/some/path"]
//     span.spinner[data-toggle-target="spinner" style="display:none"]
//
// Optional:
//   data-toggle-confirm-value="Are you sure?" — shows confirm dialog
//   data-toggle-method-value="put" — HTTP method (default: PUT)
//   data-toggle-reload-value="true" — reload page after success

(function() {
  var ToggleController = class extends Stimulus.Controller {
    static get targets() { return ["checkbox", "spinner"]; }
    static get values() { return { url: String, confirm: String, method: String, reload: Boolean }; }

    toggle(event) {
      event.preventDefault();
      var _this = this;

      // Confirm dialog
      if (this.hasConfirmValue && this.confirmValue) {
        if (!confirm(this.confirmValue)) return;
      }

      var url = this.hasUrlValue ? this.urlValue : this.checkboxTarget.dataset.url;
      var method = this.hasMethodValue ? this.methodValue : "PUT";

      // Show spinner
      if (this.hasSpinnerTarget) this.spinnerTarget.style.display = "";

      var csrfToken = document.querySelector('meta[name="csrf-token"]');
      var headers = {
        "Content-Type": "application/x-www-form-urlencoded; charset=utf-8",
        "Accept": "application/json",
        "X-Requested-With": "XMLHttpRequest"
      };
      if (csrfToken) headers["X-CSRF-Token"] = csrfToken.content;

      fetch(url, { method: method, headers: headers, credentials: "same-origin" })
        .then(function(response) { return response.json(); })
        .then(function(data) {
          if (data.status === "ok") {
            if (_this.hasCheckboxTarget) {
              var cb = _this.checkboxTarget;
              cb.checked = !cb.checked;
            }
            if (typeof data.force !== "undefined" && _this.hasCheckboxTarget) {
              _this.checkboxTarget.checked = data.force;
            }
            _this.dispatch("success", { detail: data });
          } else {
            _this.dispatch("error", { detail: data });
          }
        })
        .catch(function(err) { console.error("Toggle failed:", err); })
        .finally(function() {
          if (_this.hasSpinnerTarget) _this.spinnerTarget.style.display = "none";
          if (_this.hasReloadValue && _this.reloadValue) window.location.reload();
        });
    }
  };

  registerStimulusController("toggle", ToggleController);
})();
