// Progress Controller
//
// Polls a URL at intervals, updates a progress bar and message.
// Used for app install/uninstall progress tracking.
//
// Usage:
//   div[data-controller="progress"]
//     [data-progress-url-value="/apps/install_progress/myapp"]
//     [data-progress-interval-value="2000"]
//     div.progress-bar[data-progress-target="bar" style="width: 0%"]
//     span[data-progress-target="message"]
//     div[data-progress-target="result" style="display:none"]

(function() {
  var ProgressController = class extends Stimulus.Controller {
    static get targets() { return ["bar", "message", "result"]; }
    static get values() { return { url: String, interval: Number, active: Boolean }; }

    connect() {
      if (this.hasActiveValue && this.activeValue) {
        this.startPolling();
      }
    }

    disconnect() {
      this.stopPolling();
    }

    start() {
      this.activeValue = true;
      this.startPolling();
    }

    startPolling() {
      var _this = this;
      var interval = this.hasIntervalValue ? this.intervalValue : 2000;
      this._timer = setInterval(function() { _this.poll(); }, interval);
    }

    stopPolling() {
      if (this._timer) {
        clearInterval(this._timer);
        this._timer = null;
      }
    }

    poll() {
      var _this = this;
      var csrfToken = document.querySelector('meta[name="csrf-token"]');
      var headers = {
        "Accept": "application/json",
        "X-Requested-With": "XMLHttpRequest"
      };
      if (csrfToken) headers["X-CSRF-Token"] = csrfToken.content;

      fetch(this.urlValue, { headers: headers, credentials: "same-origin" })
        .then(function(response) { return response.json(); })
        .then(function(data) {
          var progress = data.progress || 0;
          var message = data.message || "";

          if (_this.hasBarTarget) {
            _this.barTarget.style.width = Math.min(progress, 100) + "%";
          }
          if (_this.hasMessageTarget) {
            _this.messageTarget.textContent = message;
          }

          // Done (100) or error (>100)
          if (progress >= 100) {
            _this.stopPolling();
            _this.activeValue = false;

            if (data.content && _this.hasResultTarget) {
              _this.resultTarget.innerHTML = data.content;
              _this.resultTarget.style.display = "";
            }

            _this.dispatch(progress === 100 ? "complete" : "error", { detail: data });
          }
        })
        .catch(function(err) {
          console.error("Progress poll failed:", err);
        });
    }
  };

  registerStimulusController("progress", ProgressController);
})();
