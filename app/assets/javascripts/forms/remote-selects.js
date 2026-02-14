// Remote select implementation
//
// options
//   selector - css selector for selects
//   custom callbacks:
//     beforeSend(RemoteSelect, select)
//     success(RemoteSelect, select)
//     complete(RemoteSelect, select)
//   spinnerParentSelector - where should search for .spinner
//
window.RemoteSelect = {
  initialize: function(options) {
    var _this = this;
    options = options || {};
    $(document).on("change", options["selector"], function() {
      options["beforeSend"] = options["beforeSend"] || function() {};
      options["success"] = options["success"] || function() {};
      options["complete"] = options["complete"] || function() {};
      options["spinnerParentSelector"] = options["spinnerParentSelector"] || "span:first";
      options["parentSelector"] = options["parentSelector"] || false;
      var select = $(this);
      select.blur();
      var run_request;
      if (typeof select.data("confirm") === "undefined") {
        run_request = true;
      } else {
        run_request = confirm(select.data("confirm"));
      }
      if (run_request && typeof select.data("request") === "undefined") {
        var request_data = {};
        request_data[select.attr('name')] = select.val();
        $.ajax({
          beforeSend: function() {
            select.data("request", true);
            _this.toggle_spinner(options["spinnerParentSelector"], select);
            options["beforeSend"](_this, select);
          },
          type: "PUT",
          data: request_data,
          url: _this.url(select),
          success: function(data) {
            if (data["status"] === "ok") {
              options["success"](_this, select, data);
            }
          },
          complete: function() {
            try {
              _this.toggle_spinner(options["spinnerParentSelector"], select);
              options["complete"](_this, select);
              if (options["parentSelector"]) {
                _this.highlight_parent(options["parentSelector"], select);
              }
              select.removeData("request");
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
