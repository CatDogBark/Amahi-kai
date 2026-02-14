//
// Remote Radios
//
// options
//   selector - css selector for radios
//   custom callbacks:
//     beforeSend(RemoteRadio, radio)
//     success(RemoteRadio, radio)
//     complete(RemoteRadio, radio)
//   spinnerParentSelector - where should search for .spinner
//
window.RemoteRadio = {
  initialize: function(options) {
    var _this = this;
    options = options || {};
    $(document).on("click", options["selector"], function() {
      options["beforeSend"] = options["beforeSend"] || function() {};
      options["success"] = options["success"] || function() {};
      options["complete"] = options["complete"] || function() {};
      options["spinnerParentSelector"] = options["spinnerParentSelector"] || "p:first";
      options["parentSelector"] = options["parentSelector"] || false;
      var radio = $(this);
      radio.blur();
      var run_request;
      if (typeof radio.data("confirm") === "undefined") {
        run_request = true;
      } else {
        run_request = confirm(radio.data("confirm"));
      }
      if (run_request && typeof radio.data("request") === "undefined") {
        var request_data = {};
        request_data[radio.attr('name')] = radio.val();
        $.ajax({
          beforeSend: function() {
            radio.data("request", true);
            _this.toggle_spinner(options["spinnerParentSelector"], radio);
            options["beforeSend"](_this, radio);
          },
          type: "PUT",
          data: request_data,
          url: _this.url(radio),
          success: function(data) {
            if (data["status"] === "ok") {
              options["success"](_this, radio, data);
              radio.prop("checked", !radio.prop("checked"));
            }
            if (typeof data["force"] !== "undefined") {
              radio.prop("checked", data["force"]);
            }
          },
          complete: function() {
            try {
              _this.toggle_spinner(options["spinnerParentSelector"], radio);
              options["complete"](_this, radio);
              if (options["parentSelector"]) {
                _this.highlight_parent(options["parentSelector"], radio);
              }
              radio.removeData("request");
            } catch(e) {}
          }
        });
      }
      return false;
    });
  },

  url: function(element) {
    return $(element).data("url");
  },

  toggle_spinner: function(spinnerParentSelector, element) {
    $(element).parents(spinnerParentSelector).find(".spinner:first").toggle();
  },

  highlight_parent: function(parentSelector, element) {
    $(element).parents(parentSelector).effect("highlight");
  }
};
