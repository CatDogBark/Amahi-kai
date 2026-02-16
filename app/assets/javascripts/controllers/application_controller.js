// Stimulus Application Setup
//
// Since we're using Sprockets (not importmap), we manually register controllers.
// Turbo Drive is disabled globally via data-turbo="false" on <body>.
// We only use Turbo Frames/Streams where explicitly opted in.

(function() {
  window.StimulusApp = Stimulus.Application.start();

  // Helper to register controllers from Sprockets-loaded files
  window.registerStimulusController = function(name, controllerClass) {
    window.StimulusApp.register(name, controllerClass);
  };

  // Shared CSRF helper for fetch requests
  window.csrfHeaders = function() {
    var token = document.querySelector('meta[name="csrf-token"]');
    var headers = {
      "Accept": "application/json",
      "X-Requested-With": "XMLHttpRequest"
    };
    if (token) headers["X-CSRF-Token"] = token.content;
    return headers;
  };
})();
