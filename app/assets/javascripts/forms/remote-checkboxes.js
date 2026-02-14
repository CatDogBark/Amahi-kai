//
// Remote Checkboxes
//
// options
//   selector - css selector for checkboxes
//   custom callbacks:
//     beforeSend(RemoteCheckbox, checkbox)
//     success(RemoteCheckbox, checkbox)
//     complete(RemoteCheckbox, checkbox)
//   spinnerParentSelector - where should search for .spinner
//
window.RemoteCheckbox = {
  initialize: function(options) {
    var _this = this;
    options = options || {};
    $(document).on("click", options["selector"], function() {
      options["beforeSend"] = options["beforeSend"] || function() {};
      options["success"] = options["success"] || function() {};
      options["complete"] = options["complete"] || function() {};
      options["spinnerParentSelector"] = options["spinnerParentSelector"] || "span:first";
      options["parentSelector"] = options["parentSelector"] || false;
      var checkbox = $(this);
      checkbox.blur();
      var run_request;
      if (typeof checkbox.data("confirm") === "undefined") {
        run_request = true;
      } else {
        run_request = confirm(checkbox.data("confirm"));
      }
      if (run_request && typeof checkbox.data("request") === "undefined") {
        $.ajax({
          beforeSend: function() {
            checkbox.data("request", true);
            _this.toggle_spinner(options["spinnerParentSelector"], checkbox);
            options["beforeSend"](_this, checkbox);
          },
          type: "PUT",
          url: _this.url(checkbox),
          success: function(data) {
            if (data["status"] === "ok") {
              options["success"](_this, checkbox, data);
              checkbox.prop("checked", !checkbox.prop("checked"));
            }
            if (typeof data["force"] !== "undefined") {
              checkbox.prop("checked", data["force"]);
            }
          },
          complete: function() {
            try {
              _this.toggle_spinner(options["spinnerParentSelector"], checkbox);
              options["complete"](_this, checkbox);
              if (options["parentSelector"]) {
                _this.highlight_parent(options["parentSelector"], checkbox);
              }
              checkbox.removeData("request");
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
