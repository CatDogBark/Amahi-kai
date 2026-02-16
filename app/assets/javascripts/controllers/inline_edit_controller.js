// Inline Edit Controller
//
// Replaces SmartLinks pattern: click to show inline edit form,
// submit via AJAX, update display on success.
//
// Usage:
//   div[data-controller="inline-edit"]
//     span[data-inline-edit-target="display" data-action="click->inline-edit#edit"]
//       | Current Value
//     form[data-inline-edit-target="form" style="display:none"]
//       [data-action="submit->inline-edit#submit"]
//       input[data-inline-edit-target="input"]
//       button[type="submit"] Save
//       button[type="button" data-action="click->inline-edit#cancel"] Cancel
//     span.messages[data-inline-edit-target="message"]
//     span.spinner[data-inline-edit-target="spinner" style="display:none"]

(function() {
  var InlineEditController = class extends Stimulus.Controller {
    static get targets() { return ["display", "form", "input", "message", "spinner"]; }
    static get values() { return { url: String, method: String, paramName: String }; }

    edit(event) {
      if (event) event.preventDefault();
      if (this.hasInputTarget && this.hasDisplayTarget) {
        this.inputTarget.value = this.displayTarget.textContent.trim();
      }
      if (this.hasDisplayTarget) this.displayTarget.style.display = "none";
      if (this.hasFormTarget) {
        this.formTarget.style.display = "";
        if (this.hasInputTarget) this.inputTarget.focus();
      }
    }

    cancel(event) {
      if (event) event.preventDefault();
      if (this.hasFormTarget) this.formTarget.style.display = "none";
      if (this.hasDisplayTarget) this.displayTarget.style.display = "";
    }

    submit(event) {
      event.preventDefault();
      var _this = this;
      var url = this.hasUrlValue ? this.urlValue : this.formTarget.action;
      var method = this.hasMethodValue ? this.methodValue : "PUT";

      if (this.hasSpinnerTarget) this.spinnerTarget.style.display = "";

      var csrfToken = document.querySelector('meta[name="csrf-token"]');
      var headers = {
        "Content-Type": "application/x-www-form-urlencoded; charset=utf-8",
        "Accept": "application/json",
        "X-Requested-With": "XMLHttpRequest"
      };
      if (csrfToken) headers["X-CSRF-Token"] = csrfToken.content;

      var body = new URLSearchParams(new FormData(this.formTarget)).toString();

      fetch(url, { method: method, headers: headers, body: body, credentials: "same-origin" })
        .then(function(response) { return response.json(); })
        .then(function(data) {
          if (data.status === "ok") {
            if (_this.hasDisplayTarget && data.name) {
              _this.displayTarget.textContent = data.name;
            }
            _this.cancel();
            _this.showMessage(data.message || "Saved");
          } else {
            _this.showMessage(data.message || "Error", true);
          }
          _this.dispatch("complete", { detail: data });
        })
        .catch(function(err) {
          console.error("Inline edit failed:", err);
          _this.showMessage("Request failed", true);
        })
        .finally(function() {
          if (_this.hasSpinnerTarget) _this.spinnerTarget.style.display = "none";
        });
    }

    showMessage(text, isError) {
      var _this = this;
      if (this.hasMessageTarget) {
        this.messageTarget.textContent = text;
        if (isError) this.messageTarget.classList.add("text-danger");
        else this.messageTarget.classList.remove("text-danger");
        setTimeout(function() { _this.messageTarget.textContent = ""; }, 8000);
      }
    }
  };

  registerStimulusController("inline-edit", InlineEditController);
})();
