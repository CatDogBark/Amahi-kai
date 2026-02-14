var Servers = {
  initialize: function() {
    $(document).on('ajax:success', '.btn-refresh, .btn-start, .btn-stop, .btn-restart', function(data, results) {
      var link = $(this);
      var content = $(results["content"]);
      content.find('.settings-stretcher').show();
      link.parents('.server').replaceWith(content);
    });

    RemoteCheckbox.initialize({
      selector: ".server_monitored_checkbox, .server_start_at_boot_checkbox",
      success: function(rc, checkbox, data) {
        var content = $(data["content"]);
        content.find('.settings-stretcher').show();
        $(checkbox).parents('.server').replaceWith(content);
      }
    });
  }
};

$(function() {
  Servers.initialize();
});

// reload the page with locale change because the whole language has changed
$(function() {
  $(".preftab").on("ajax:success", "#locale", function() {
    window.location.reload(true);
  });
});

$(document).on("click", ".remote-check", function(event) {
  var checkbox = $(this);
  checkbox.prop("checked", !checkbox.prop("checked"));
  return true;
});

$(document).on("ajax:complete", ".remote-check", function() {
  $(this).prop("checked", !$(this).prop("checked"));
});
