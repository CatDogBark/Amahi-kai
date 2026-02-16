// Locale Controller
//
// Sends locale change request, reloads the page on success.
//
// Usage:
//   select[data-controller="locale"]
//     [data-action="change->locale#update"]
//     [data-locale-url-value="/tab/settings/change_language"]

(function() {
  var LocaleController = class extends Stimulus.Controller {
    static get values() { return { url: String }; }

    update(event) {
      var locale = this.element.value;
      var url = this.urlValue;

      var headers = csrfHeaders();
      headers["Content-Type"] = "application/x-www-form-urlencoded; charset=utf-8";

      fetch(url, {
        method: "POST",
        headers: headers,
        body: "locale=" + encodeURIComponent(locale),
        credentials: "same-origin"
      })
        .then(function(response) { return response.json(); })
        .then(function(data) {
          if (data.status === "ok") {
            window.location.reload(true);
          }
        })
        .catch(function(err) { console.error("Locale change failed:", err); });
    }
  };

  registerStimulusController("locale", LocaleController);
})();
