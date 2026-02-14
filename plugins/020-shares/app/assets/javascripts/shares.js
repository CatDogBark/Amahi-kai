// Amahi Home Server
// Copyright (C) 2007-2013 Amahi
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License v3
// (29 June 2007), as published in the COPYING file.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// file COPYING for more details.
//
// You should have received a copy of the GNU General Public
// License along with this program; if not, write to the Amahi
// team at http://www.amahi.org/ under "Contact Us."

// Shares JS functionality

var Shares = {
  initialize: function() {
    var _this = this;

    // new share
    $(document).on("ajax:success", "#new-share-form", function(data, results) {
      if (results["status"] !== "ok") {
        _this.form().replaceWith(results["content"]);
      } else {
        var parent = $("#shares-table");
        parent.replaceWith(results["content"]);
      }
    });

    $(document).on("blur", "#share_comment", function() {
      var share_comment = $(this);
      var share_path = $("#share_path");
      if (share_comment.val() !== "" && share_path.val() === "") {
        share_path.val(share_path.data("pre") + share_comment.val());
        FormHelpers.focus(share_path);
      }
    });

    // deleting a share
    $(document).on("ajax:success", ".btn-delete", function() {
      var share = _this.share($(this));
      share.remove();
    });

    // update workgroup
    $(document).ready(function() {
      $(".workgroup_click_change").click(function() {
        $(this).hide();
        $(this).parent().find(".edit_workgroup_form").show();
      });

      $(".workgroup_cancel_link").click(function() {
        var id = $(this).data("id");
        var form = "#div_form_" + id;
        $(form).find('form').hide();
        $(form).parent().find(".workgroup_click_change").show();
      });
    });

    $(document).on("ajax:success", ".edit_workgroup_form", function(event, results) {
      var element = $(".workgroup_click_change");
      var msg = $(this).parent().parent().find(".messages");
      msg.html(results.message);
      setTimeout(function() { msg.html(""); }, 8000);
      if (results.status === 'ok') {
        element.html($(".edit_workgroup_form > input").val());
        $(this).hide('slow');
        $(this).parent().parent().find(".workgroup_click_change").val(results.name);
        $(this).parent().parent().find(".workgroup_click_change").show();
      }
    });

    RemoteCheckbox.initialize({
      selector: ".share_visible_checkbox",
      parentSelector: "span:first"
    });

    RemoteCheckbox.initialize({
      selector: ".share_everyone_checkbox, .share_access_checkbox, .share_guest_access_checkbox",
      parentSelector: "span:first",
      spinnerParentSelector: ".access",
      success: function(rc, checkbox, data) {
        _this.update_access_area(checkbox, data["content"]);
      }
    });

    RemoteCheckbox.initialize({
      selector: ".share_readonly_checkbox, .share_write_checkbox, .share_guest_writeable_checkbox",
      parentSelector: "span:first",
      spinnerParentSelector: ".access"
    });

    // update tags
    SmartLinks.initialize({
      open_selector: ".open-update-tags-area",
      close_selector: ".close-update-tags-area",
      onShow: function(open_link) {
        var share = _this.share(open_link);
        var share_id = _this.parse_id(share.attr("id"));
        open_link.after(Templates.run("updateTags", { share_id: share_id }));
        var form = open_link.next();
        FormHelpers.update_first(form, open_link.text());
        FormHelpers.focus_first(form);
      }
    });

    $(document).on("ajax:success", ".update-tags-form", function(data, results) {
      var form = $(this);
      var share = _this.share(form);
      share.find(".tags:first").replaceWith(results["content"]);
    });

    RemoteCheckbox.initialize({
      selector: ".share_tags_checkbox",
      parentSelector: "span:first",
      spinnerParentSelector: ".tags",
      success: function(rc, checkbox, data) {
        checkbox = $(checkbox);
        var share = _this.share(checkbox);
        share.find(".tags:first").replaceWith(data["content"]);
      }
    });

    // update path
    SmartLinks.initialize({
      open_selector: ".open-update-path-area",
      close_selector: ".close-update-path-area",
      onShow: function(open_link) {
        var share = _this.share(open_link);
        var share_id = _this.parse_id(share.attr("id"));
        open_link.after(Templates.run("updatePath", { share_id: share_id }));
        var form = open_link.next();
        FormHelpers.update_first(form, open_link.text());
        FormHelpers.focus_first(form);
      }
    });

    $(document).on("ajax:success", ".update-path-form", function(data, results) {
      if (results["status"] === "ok") {
        var form = $(this);
        var link = form.prev();
        var value = FormHelpers.find_first(form).val();
        link.text(value);
      }
    });

    $(document).on("ajax:complete", ".update-path-form", function() {
      var form = $(this);
      var link = form.prev();
      form.hide("slow", function() {
        form.remove();
        link.show();
      });
    });

    RemoteCheckbox.initialize({
      selector: ".disk_pooling_checkbox",
      parentSelector: "span:first"
    });

    RemoteCheckbox.initialize({
      selector: ".disk_pool_checkbox",
      parentSelector: "span:first",
      success: function(rc, checkbox, data) {
        checkbox = $(checkbox);
        var share = _this.share(checkbox);
        share.find(".disk-pool:first").replaceWith(data["content"]);
      }
    });

    // update size
    $('.update-size-area').on("ajax:success", function(data, results) {
      $('.size' + results.id).text(results.size);
    });

    // update extras
    SmartLinks.initialize({
      open_selector: ".open-update-extras-area",
      close_selector: ".close-update-extras-area",
      onShow: function(open_link) {
        var share = _this.share(open_link);
        var share_id = _this.parse_id(share.attr("id"));
        open_link.after(Templates.run("updateExtras", { share_id: share_id }));
        var form = open_link.next();
        FormHelpers.update_first(form, open_link.text());
        FormHelpers.focus_first(form);
      }
    });

    $(document).on("ajax:success", ".update-extras-form", function(data, results) {
      if (results["status"] === "ok") {
        var form = $(this);
        var link = form.prev();
        var text_area = FormHelpers.find_first(form);
        var value = $.trim(text_area.val());
        value = (value === "") ? text_area.attr("placeholder") : value;
        link.text(value);
      }
    });

    $(document).on("ajax:complete", ".update-extras-form", function(data, results) {
      var form = $(this);
      var link = form.prev();
      form.hide("slow", function() {
        form.remove();
        link.show();
      });
    });

    $(document).on("ajax:success", ".clear-permissions", function(data, results) {
      var link = $(this);
      var parent = link.parent();
      if (results["status"] === "ok") {
        parent.html(FormHelpers.ok_icon);
      } else {
        parent.html(FormHelpers.error_icon);
      }
    });
  },

  parse_id: function(html_id) {
    var parts = html_id.split("_");
    return parts[parts.length - 1];
  },

  share: function(finder) {
    return (typeof finder === "string") ? this.share_by_id(finder) : this.share_by_element(finder);
  },

  share_by_element: function(element) {
    return $(element).parents(".share");
  },

  share_by_id: function(id) {
    return $("#whole_share_" + id);
  },

  access_area: function(element) {
    return this.share(element).find(".access:first");
  },

  update_access_area: function(element, content) {
    this.access_area(element).html(content);
  },

  form: function(element) {
    return element ? $(element).parents("form:first") : $("#new-share-form");
  }
};

$(document).ready(function() {
  Shares.initialize();
});
