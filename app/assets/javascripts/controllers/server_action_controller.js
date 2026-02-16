// Server Action Controller
//
// Handles server refresh/start/stop/restart actions and checkbox toggles.
// Replaces the entire server element with the response HTML.
//
// Usage:
//   div.server[data-controller="server-action"]
//     a[data-action="click->server-action#perform"]
//       [data-server-action-url-value="/settings/servers/1/start"]
//       [data-server-action-confirm-value="Are you sure?"]
//     input[type="checkbox"][data-action="click->server-action#perform"]
//       [data-server-action-url-value="/settings/servers/1/toggle_monitored"]

(function() {
  var ServerActionController = class extends Stimulus.Controller {
    static get values() { return { }; }

    perform(event) {
      event.preventDefault();
      var _this = this;
      var target = event.currentTarget;
      var url = target.dataset.url || target.dataset.serverActionUrl;
      var confirmMsg = target.dataset.confirm || target.dataset.serverActionConfirm;
      var method = target.dataset.method || "POST";

      if (confirmMsg && !confirm(confirmMsg)) return;

      // Find and show spinner
      var spinner = target.parentElement.querySelector('.spinner');
      if (spinner) spinner.style.display = '';

      var csrfToken = document.querySelector('meta[name="csrf-token"]');
      var headers = {
        "Accept": "application/json",
        "X-Requested-With": "XMLHttpRequest"
      };
      if (csrfToken) headers["X-CSRF-Token"] = csrfToken.content;

      fetch(url, { method: method, headers: headers, credentials: "same-origin" })
        .then(function(response) { return response.json(); })
        .then(function(data) {
          if (data.content) {
            var temp = document.createElement('div');
            temp.innerHTML = data.content;
            var newElement = temp.firstElementChild;
            // Show the stretcher (detail panel) in the replacement
            var stretcher = newElement.querySelector('.settings-stretcher');
            if (stretcher) stretcher.style.display = '';
            _this.element.replaceWith(newElement);
          }
        })
        .catch(function(err) {
          console.error("Server action failed:", err);
          if (spinner) spinner.style.display = 'none';
        });
    }
  };

  registerStimulusController("server-action", ServerActionController);
})();
