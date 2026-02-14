// Amahi Home Server - Apps JS functionality

var Apps = {
  initialize: function() {
    var _this = this;

    $(document).on("ajax:beforeSend", ".install-app-in-background", function() {
      $(".install-button").hide();
      _this.toggle_spinner(this);
      $('.app').each(function() {
        $(this).find('.install-app-in-background').addClass('inactive');
      });
    });

    $(document).on("ajax:beforeSend", ".uninstall-app-in-background", function() {
      _this.toggle_spinner(this);
      $('.app').each(function() {
        $(this).find('.install-app-in-background').addClass('inactive');
        $(this).find('.install-button').addClass('inactive');
      });
    });

    $(document).on("ajax:success", ".install-app-in-background, .uninstall-app-in-background", function(data, results) {
      _this.update_progress(results["identifier"], results["content"]);
      _this.trace_progress(results["identifier"]);
    });

    RemoteCheckbox.initialize({
      selector: ".in_dashboard_checkbox",
      parentSelector: "span:first"
    });
  },

  app: function(finder) {
    return (typeof finder === "string") ? this.app_by_identifier(finder) : this.app_by_element(finder);
  },

  app_by_element: function(element) {
    return $(element).parents(".app:first");
  },

  app_by_identifier: function(identifier) {
    return $("#app_whole_" + identifier);
  },

  toggle_spinner: function(finder) {
    var app = this.app(finder);
    app.find(".spinner").toggle();
  },

  progress: function(finder) {
    return this.app(finder).find(".progress-status:first");
  },

  update_progress: function(finder, content) {
    this.progress(finder).html(content);
  },

  update_progress_bar: function(finder, progress) {
    if (progress >= 0 && progress <= 100) {
      var message = this.app(finder).get(0).querySelector(".message");
      if (message) {
        message.style.display = "none";
      }
      var progress_bar_div = this.app(finder).get(0).querySelector(".progress-bar-div");
      var progress_bar = progress_bar_div.querySelector(".progress-bar");
      progress_bar_div.style.display = "inline-block";
      progress_bar.innerHTML = progress + "%";
      progress_bar.style.width = progress + "%";
    }
  },

  progress_message: function(finder) {
    return this.app(finder).find(".install_progress");
  },

  update_progress_message: function(finder, content) {
    this.progress_message(finder).html(content);
  },

  show_app_flash_notice: function(finder) {
    var app = this.app(finder);
    var notice = app.find(".app-flash-notice");
    notice.show();
  },

  update_installed_app: function(finder, content) {
    var _this = this;
    var app = this.app(finder);
    app.replaceWith(content);
    _this.show_app_flash_notice(finder);
    $(".install-button").show();
  },

  update_uninstalled_app: function(finder) {
    this.app(finder).remove();
    $('.app').each(function() {
      $(".install-button").show();
    });
  },

  show_uninstall_button: function(finder) {
    this.progress(finder).get(0).querySelector(".install-button").style.display = "inline-block";
    var progress_bar_div = this.app(finder).get(0).querySelector(".progress-bar-div");
    progress_bar_div.style.display = "none";
    this.app(finder).get(0).querySelector(".spinner").style.display = "none";
    this.app(finder).get(0).querySelector(".app-flash-notice").style.display = "none";
    var uninstall_progress = this.app(finder).get(0).querySelector(".uninstall_progress");
    uninstall_progress.innerHTML = "Some error occurred during uninstallation.";
    uninstall_progress.style.display = "inline-block";
  },

  show_error_message_installed_tab: function(finder, content) {
    var message = this.progress(finder).get(0).querySelector(".uninstall_progress");
    message.innerHTML = content;
  },

  show_error_message_available_tab: function(finder, content) {
    var message = this.app(finder).get(0).querySelector(".message");
    message.style.display = "inline-block";
    message.innerHTML = content;
    this.app(finder).get(0).querySelector(".spinner").style.display = "none";
  },

  trace_progress: function(finder) {
    var _this = this;
    $.ajax({
      url: _this.app(finder).data("progressPath"),
      success: function(data) {
        var progress = data["progress"];
        var timeout_t = 0;

        if (data["type"].indexOf("uninstall") !== -1) {
          progress = 100 - progress;
          if (progress === 0) {
            timeout_t = 2000;
          }
        } else {
          if (progress === 100) {
            timeout_t = 2000;
          }
        }

        _this.update_progress_bar(finder, progress);
        _this.update_progress_message(finder, data["content"]);

        if (progress === 950) {
          $('.app').each(function() {
            $(this).find('.install-app-in-background').removeClass('inactive');
          });
          _this.show_error_message_available_tab(finder, data["content"]);

        } else if (data["app_content"]) {
          setTimeout(function() {
            _this.update_installed_app(finder, data["app_content"]);
            $('.app').each(function() {
              $(this).find('.install-app-in-background').removeClass('inactive');
              $(this).find('.install-button').removeClass('inactive');
            });
          }, timeout_t);

        } else if (data["uninstalled"]) {
          setTimeout(function() {
            $('.app').each(function() {
              $(this).find('.install-app-in-background').removeClass('inactive');
              $(this).find('.install-button').removeClass('inactive');
            });
            _this.update_uninstalled_app(finder);
          }, 2000);

        } else if (progress === -899) { // 100-999
          setTimeout(function() {
            $('.app').each(function() {
              $(this).find('.install-app-in-background').removeClass('inactive');
              $(this).find('.install-button').removeClass('inactive');
            });
            _this.show_uninstall_button(finder);
          }, 2000);

        } else if (progress === -850) { // 100-950
          $('.app').each(function() {
            $(this).find('.install-button').removeClass('inactive');
          });
          _this.show_uninstall_button(finder);
          _this.show_error_message_installed_tab(finder, data["content"]);

        } else {
          setTimeout(function() { Apps.trace_progress(finder); }, 2000);
        }
      }
    });
  }
};

$(document).ready(function() {
  Apps.initialize();
});
