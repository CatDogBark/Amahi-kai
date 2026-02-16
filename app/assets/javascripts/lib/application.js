$(document).ready(function() {
  // Stretch-toggle: expand/collapse settings panels
  $(".preftab").on("click", ".stretchtoggle", function() {
    $(this).parents("div:first").find(".settings-stretcher:first").toggle('slow');
    return false;
  });

  // Open/close new entry form areas
  $(document).on("click", ".open-area", function(event) {
    event.preventDefault();
    var related = $(this).data("related");
    $(related).slideToggle();
  });

  $(document).on("click", ".close-area", function(event) {
    event.preventDefault();
    var related = $(this).data("related");
    $(related).slideUp();
  });

  // Hover highlight for focusable elements
  $(".focus").on({
    mouseenter: function() {
      $(this).css("background-color", "rgb(255,255,153)");
    },
    mouseleave: function() {
      $(this).css("background-color", "transparent");
    }
  });

  // Search form target switching
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
