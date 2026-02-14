var Users = {
  parse_id: function(html_id) {
    var parts = html_id.split("_");
    return parts[parts.length - 1];
  },

  user: function(finder) {
    return (typeof finder === "string") ? this.user_by_id(finder) : this.user_by_element(finder);
  },

  user_by_element: function(element) {
    return $(element).parents(".user:first");
  },

  user_by_id: function(id) {
    return $("#whole_user_" + id);
  },

  toggle_delete_area: function(element) {
    this.user(element).find(".delete:first").toggle();
  },

  form: function(element) {
    return element ? $(element).parents("form:first") : $("#new-user-form");
  },

  initialize: function() {
    var _this = this;
    SmartLinks.initialize({
      open_selector: ".open-username-edit",
      close_selector: ".close-username-edit",
      onShow: function(open_link) {
        var user = _this.user(open_link);
        var user_id = _this.parse_id(user.prop("id"));
        open_link.after(Templates.run("updateUsername", { user_id: user_id }));
        var form = open_link.next();
        FormHelpers.update_first(form, open_link.text());
        FormHelpers.focus_first(form);
      }
    });
    RemoteCheckbox.initialize({
      selector: ".user_admin_checkbox",
      parentSelector: "span:first",
      success: function(rc, checkbox) {
        _this.user(checkbox).find(".user_icons:first").toggleClass("user_admin");
        _this.toggle_delete_area(checkbox);
      }
    });
  }
};

$(function() {
  $(document)

    // new user
    .on('ajax:success', '#new-user-form', function(event, results) {
      var form = $(this);
      if (results['errors']) {
        console.log(results);
        form.replaceWith(results["content"]);
        return;
      } else {
        $('#users-table').parent().html(results["content"]);
        form.find("input[type=text], input[type=password]").val("");
      }
    })

    // delete a user
    .on("ajax:success", ".btn-delete", function(event, results) {
      var user = $("#whole_user_" + results["id"]);
      if (results["status"] !== "ok") {
        alert(results["status"]);
        $(this).parent().find(".spinner").hide();
        $(this).show();
      } else {
        user.hide("slow", function() {
          user.remove();
        });
      }
    })

    .on("ajax:success", ".edit_name_form", function(event, results) {
      var element = "#whole_user_" + results.id;
      var msg = $(element).find(".messages");
      msg.html(results.message);
      setTimeout(function() { msg.html(""); }, 8000);
      var id = results["id"];
      var textElement = $("#text_user_" + results["id"]);
      textElement.val(results["name"]);
      if (results.status === "ok") {
        var col_element = $("#whole_user_" + results["id"]);
        $(this).hide('slow');
        var elem = $(this).closest('td').find(".name_click_change");
        elem.html(results["name"]);
        elem.show();
        col_element.find(".users-col2").html(results["name"]);
      }
    })

    // update user password
    .on('ajax:success', '.update-password', function(event, results) {
      var msg = $(this).find(".messages:first");
      msg.html(results["message"]);
      setTimeout(function() { msg.html(""); }, 8000);
      if (results.status === 'ok') {
        $(this).find("input[type=password]").val("");
        $(this).find(".password-edit").hide("slow");
      }
    })

    // update user pin
    .on('ajax:success', '.update-pin', function(event, results) {
      var msg = $(this).find(".messages:first");
      msg.html(results["message"]);
      setTimeout(function() { msg.html(""); }, 8000);
      if (results.status === 'ok') {
        $(this).find("input[type=password]").val("");
        $(this).find(".pin-edit").hide("slow");
      }
    })

    // management of the public key area
    .on('ajax:success', '.update-pubkey', function(event, results) {
      var form = $(this);
      var image;
      if (results["status"] === "ok") {
        image = form.parent().parent().children(".ok");
      } else {
        image = form.parent().parent().children(".error");
      }
      image.show();
      setTimeout(function() { image.hide("slow"); }, 3000);
    })

    .on('ajax:beforeSend', '.update-pubkey', function() {
      var form = $(this);
      form.parent().hide('slow');
    })

    // username editing
    .on('ajax:success', '.username-form', function(event, results) {
      if (results["status"] === "ok") {
        var form = $(this);
        var link = form.prev();
        var value = FormHelpers.find_first(form).val();
        link.text(value);
      }
    })

    .on('ajax:complete', '.username-form', function(event, results) {
      var form = $(this);
      var link = form.prev();
      form.hide("slow", function() {
        form.remove();
        link.show();
      });
    })

    // update fullname
    .ready(function() {
      $(".name_click_change").click(function() {
        $(this).hide();
        $(this).parent().find(".edit_name_form").show();
      });

      $(".name_cancel_link").click(function() {
        var id = $(this).data("id");
        var element = "#whole_user_" + id;
        var form = $(element).find('.edit_name_form');
        form.hide();
        $(element).find(".name_click_change").show();
      });

      Users.initialize();
    });
});
