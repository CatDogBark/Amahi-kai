// Create Form Controller
//
// Handles AJAX form submission for creating new records.
// On success, replaces the target container with response HTML.
// On validation errors, replaces the form with error HTML.
//
// Usage:
//   form[data-controller="create-form"]
//     [data-action="submit->create-form#submit"]
//     [data-create-form-target-value="#users-table"]

(function() {
  var CreateFormController = class extends Stimulus.Controller {
    static get values() { return { target: String }; }

    submit(event) {
      event.preventDefault();
      var _this = this;
      var form = this.element;
      var url = form.action;
      var method = form.method || "POST";

      var headers = csrfHeaders();
      var body = new FormData(form);

      fetch(url, { method: method, headers: headers, body: body, credentials: "same-origin" })
        .then(function(r) { return r.json(); })
        .then(function(data) {
          if (data.errors) {
            // Validation errors — replace form with error version
            if (data.content) {
              var temp = document.createElement('div');
              temp.innerHTML = data.content;
              var newEl = temp.firstElementChild || temp;
              _this.element.replaceWith(newEl);
              // Ensure the form's parent containers are visible (open/close areas)
              var parent = newEl.closest('.area');
              if (parent) parent.style.display = '';
            }
          } else if (data.content) {
            // Success — replace target container and clear form
            var targetEl = document.querySelector(_this.targetValue);
            if (targetEl) {
              targetEl.parentElement.innerHTML = data.content;
            }
            form.querySelectorAll("input[type=text], input[type=password]").forEach(
              function(i) { i.value = ""; }
            );
          }
          _this.dispatch("complete", { detail: data });
        })
        .catch(function(err) { console.error("Form submit failed:", err); });
    }
  };

  registerStimulusController("create-form", CreateFormController);
})();
