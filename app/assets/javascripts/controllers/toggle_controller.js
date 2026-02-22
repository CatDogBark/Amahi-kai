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
//
// Optional:
//   data-toggle-confirm-value="Are you sure?" — shows confirm dialog
//   data-toggle-method-value="put" — HTTP method (default: PUT)
//   data-toggle-reload-value="true" — reload page after success
//   data-toggle-target="spinner" — custom spinner element (auto-created if missing)

(function() {
  var ToggleController = class extends Stimulus.Controller {
    static get targets() { return ["checkbox", "spinner"]; }
    static get values() { return { url: String, confirm: String, method: String, reload: Boolean }; }

    toggle(event) {
      event.preventDefault();
      var _this = this;

      if (this.hasConfirmValue && this.confirmValue) {
        if (!confirm(this.confirmValue)) return;
      }

      var url = this.hasUrlValue ? this.urlValue : this.checkboxTarget.dataset.url;
      var method = this.hasMethodValue ? this.methodValue : "PUT";

      // Disable checkbox during request
      if (this.hasCheckboxTarget) this.checkboxTarget.disabled = true;

      // Show spinner (auto-create inline spinner if no target defined)
      var spinner = null;
      if (this.hasSpinnerTarget) {
        spinner = this.spinnerTarget;
        spinner.style.display = "";
      } else if (this.hasCheckboxTarget) {
        spinner = document.createElement("span");
        spinner.className = "spinner-border spinner-border-sm ms-1 text-muted";
        spinner.setAttribute("role", "status");
        this.checkboxTarget.parentNode.insertBefore(spinner, this.checkboxTarget.nextSibling);
      }

      var headers = csrfHeaders();
      headers["Content-Type"] = "application/x-www-form-urlencoded; charset=utf-8";

      fetch(url, { method: method, headers: headers, credentials: "same-origin" })
        .then(function(response) { return response.json(); })
        .then(function(data) {
          if (data.status === "ok") {
            if (_this.hasCheckboxTarget) _this.checkboxTarget.checked = !_this.checkboxTarget.checked;
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
          // Re-enable checkbox
          if (_this.hasCheckboxTarget) _this.checkboxTarget.disabled = false;
          // Remove/hide spinner
          if (_this.hasSpinnerTarget) {
            spinner.style.display = "none";
          } else if (spinner) {
            spinner.remove();
          }
          if (_this.hasReloadValue && _this.reloadValue) window.location.reload();
        });
    }
  };

  registerStimulusController("toggle", ToggleController);
})();
