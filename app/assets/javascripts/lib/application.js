$(document).ready(function() {
  $(".preftab").on("click", ".stretchtoggle", function() {
    $(this).parents("div:first").find(".settings-stretcher:first").toggle('slow');
    return false;
  });

  SmartLinks.initialize({
    open_selector: ".open-area",
    close_selector: ".close-area"
  });

  $(".focus").on({
    mouseenter: function() {
      $(this).css("background-color", "rgb(255,255,153)");
    },
    mouseleave: function() {
      $(this).css("background-color", "transparent");
    }
  });

  $("#websearchbutton").on({
    click: function() {
      $('#searchform').attr('target', "_blank");
    }
  });

  $("#hdasearchbutton").on({
    click: function() {
      $('#searchform').attr('target', "_self");
    }
  });
});
