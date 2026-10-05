// Times written as "3 hours ago" or "in 2 hours" (relative_time_tag in ApplicationHelper) are
// worked out again every minute, when a dialog opens and when the page comes back into view.
// The server writes them only when the page loads, so a page left open after System Update
// would keep saying "Checked less than a minute ago" for hours.

// Rails' distance_of_time_in_words (without seconds), so the page reads as the server wrote it.
function relativeTimeWords(seconds) {
  var plural = function(n, unit) { return n + ' ' + unit + (n === 1 ? '' : 's'); };
  var minutes = Math.round(Math.abs(seconds) / 60);
  if (minutes < 1) return 'less than a minute';
  if (minutes < 45) return plural(minutes, 'minute');
  if (minutes < 90) return 'about 1 hour';
  if (minutes < 1440) return 'about ' + plural(Math.round(minutes / 60), 'hour');
  if (minutes < 2520) return '1 day';
  if (minutes < 43200) return plural(Math.round(minutes / 1440), 'day');
  if (minutes < 86400) return 'about ' + plural(Math.round(minutes / 43200), 'month');
  if (minutes < 525600) return plural(Math.round(minutes / 43200), 'month');
  var years = Math.floor(minutes / 525600);
  var rest = minutes % 525600;
  if (rest < 131400) return 'about ' + plural(years, 'year');
  if (rest < 394200) return 'over ' + plural(years, 'year');
  return 'almost ' + plural(years + 1, 'year');
}

function relativeTimeText(element, now) {
  var at = new Date(element.getAttribute('datetime'));
  var seconds = (now - at) / 1000;
  var text;
  if (element.dataset.relative === 'in') {
    text = seconds < 0 ? 'in ' + relativeTimeWords(seconds) : 'any moment';
  } else {
    text = relativeTimeWords(seconds) + ' ago';
  }
  if (element.dataset.capitalize) text = text.charAt(0).toUpperCase() + text.slice(1);
  if (element.dataset.clock) {
    var sameDay = at.toDateString() === now.toDateString();
    var clock = sameDay ? at.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })
                        : at.toLocaleString([], { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
    text += ' (' + clock + ')';
  }
  return text;
}

function refreshRelativeTimes() {
  var now = new Date();
  document.querySelectorAll('time[data-relative]').forEach(function(element) {
    if (isNaN(new Date(element.getAttribute('datetime')))) return;
    element.textContent = relativeTimeText(element, now);
  });
}

document.addEventListener('DOMContentLoaded', refreshRelativeTimes);
document.addEventListener('show.bs.modal', refreshRelativeTimes);
document.addEventListener('visibilitychange', function() { if (!document.hidden) refreshRelativeTimes(); });
setInterval(refreshRelativeTimes, 60 * 1000);
