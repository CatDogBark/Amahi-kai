// Report a problem (settings/report): the switch between the details with names and addresses
// taken out and as they are, and the four ways to send the report, all from this browser:
// a new GitHub issue filled in (the bug form's fields), the email app, a file, or the clipboard.
// A link can only carry so much: a report too long for one is cut there and saved as a file to
// attach.
document.addEventListener('DOMContentLoaded', function() {
  var page = document.querySelector('.kai-report');
  if (!page) return;

  var URL_MAX = 7000; // GitHub's new-issue link, all of it
  var MAILTO_MAX = 1800; // email apps cut longer links
  var CUT_NOTE = '\n\n… The rest is in the file saved with this report: attach it.';
  var what = document.getElementById('report-what');
  var expected = document.getElementById('report-expected');
  var steps = document.getElementById('report-steps');
  var details = document.getElementById('report-details');
  var scrub = document.getElementById('report-scrub');
  var status = document.getElementById('report-status');
  var texts = { scrubbed: details.value, asIs: document.getElementById('report-details-as-is').value };
  var scrubbed = true;

  // The switch: each version keeps what was changed in it.
  scrub.addEventListener('click', function() {
    texts[scrubbed ? 'scrubbed' : 'asIs'] = details.value;
    scrubbed = !scrubbed;
    details.value = texts[scrubbed ? 'scrubbed' : 'asIs'];
    scrub.setAttribute('aria-checked', scrubbed ? 'true' : 'false');
    document.getElementById('report-scrub-note').textContent = scrubbed
      ? 'Addresses, and the names of this server, its users, devices, pools, shares, folders and files, are replaced like <share-1>; the same name gets the same stand-in everywhere, so the report still makes sense. You can change any of it before you send it.'
      : 'Showing the real names and addresses. Turn the switch back on unless whoever reads the report needs them.';
  });

  function ready() {
    if (what.value.trim()) {
      what.classList.remove('is-invalid');
      return true;
    }
    what.classList.add('is-invalid');
    what.focus();
    return false;
  }

  function title() {
    var line = what.value.trim().split('\n')[0];
    return line.length > 80 ? line.slice(0, 79) + '…' : line;
  }

  // The report as one text: the person's words, then the details.
  function report() {
    var parts = ['What happened\n' + what.value.trim()];
    if (expected.value.trim()) parts.push('What I expected\n' + expected.value.trim());
    if (steps.value.trim()) parts.push('How to make it happen again\n' + steps.value.trim());
    parts.push('Amahi-kai ' + page.dataset.version + '\n\n' + details.value.trim());
    return parts.join('\n\n');
  }

  function fileName() {
    var d = new Date();
    var pad = function(n) { return (n < 10 ? '0' : '') + n; };
    return 'amahi-kai-report-' + d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) + '-' +
      pad(d.getHours()) + pad(d.getMinutes()) + '.txt';
  }

  function download(name) {
    var link = document.createElement('a');
    link.href = URL.createObjectURL(new Blob([report() + '\n'], { type: 'text/plain' }));
    link.download = name;
    document.body.appendChild(link);
    link.click();
    link.remove();
    setTimeout(function() { URL.revokeObjectURL(link.href); }, 10000);
  }

  function say(html) {
    status.innerHTML = '';
    status.appendChild(html);
    status.hidden = false;
    status.scrollIntoView({ block: 'nearest' });
  }

  function message(strong, rest) {
    var p = document.createElement('div');
    var b = document.createElement('strong');
    b.textContent = strong;
    p.appendChild(b);
    if (rest) p.appendChild(document.createTextNode(' ' + rest));
    return p;
  }

  // The issue's link with the details cut, from the end, until it fits; whether they were.
  function issueUrl() {
    var fields = {
      template: 'bug_report.yml', title: title(), version: page.dataset.version,
      'what-happened': what.value.trim(), expected: expected.value.trim(), steps: steps.value.trim(),
      storage: page.dataset.storage
    };
    var base = page.dataset.issuesUrl + '?' + Object.keys(fields).filter(function(k) { return fields[k]; })
      .map(function(k) { return k + '=' + encodeURIComponent(fields[k]); }).join('&') + '&report=';
    var text = details.value.trim();
    var url = base + encodeURIComponent(text);
    if (url.length <= URL_MAX) return { url: url, cut: false };
    var lines = text.split('\n');
    while (lines.length > 1 && (base + encodeURIComponent(lines.join('\n') + CUT_NOTE)).length > URL_MAX) lines.pop();
    return { url: base + encodeURIComponent(lines.join('\n') + CUT_NOTE), cut: true };
  }

  document.getElementById('report-github').addEventListener('click', function() {
    if (!ready()) return;
    var issue = issueUrl();
    var name = fileName();
    if (issue.cut) download(name);
    window.open(issue.url, '_blank', 'noopener');
    say(message('GitHub opened in a new tab, with your report filled in.', issue.cut
      ? 'The details were too long for the link, so the whole report was also saved as ' + name + ': drag it onto the issue before you submit it.'
      : 'Look it over there, then submit it.'));
  });

  document.getElementById('report-email').addEventListener('click', function() {
    if (!ready()) return;
    var name = fileName();
    var body = report();
    var cut = false;
    if (encodeURIComponent(body).length > MAILTO_MAX) {
      var words = report().split('\n\nAmahi-kai ' + page.dataset.version)[0];
      body = words + '\n\nAmahi-kai ' + page.dataset.version + '\n\nThe system details and logs are in ' + name + ', attached.';
      cut = true;
      download(name);
    }
    var link = document.createElement('a');
    link.href = 'mailto:' + page.dataset.email + '?subject=' + encodeURIComponent('Amahi-kai: ' + title()) +
      '&body=' + encodeURIComponent(body);
    link.click();
    say(message('Your email app should open with the report.', cut
      ? 'The details were too long for an email link, so the whole report was saved as ' + name + ': attach it before you send.'
      : 'Look it over there, then send it.'));
  });

  document.getElementById('report-download').addEventListener('click', function() {
    if (!ready()) return;
    var name = fileName();
    download(name);
    say(message('Saved as ' + name + '.', 'Attach it to an issue or an email.'));
  });

  // The clipboard API needs HTTPS, and the LAN page is plain HTTP: copy from a hidden textarea.
  document.getElementById('report-copy').addEventListener('click', function() {
    if (!ready()) return;
    var button = this;
    var area = document.createElement('textarea');
    area.value = report();
    area.setAttribute('readonly', '');
    area.className = 'visually-hidden';
    document.body.appendChild(area);
    area.select();
    var copied = false;
    try { copied = document.execCommand('copy'); } catch (e) { copied = false; }
    area.remove();
    button.textContent = copied ? 'Copied' : "Couldn't copy";
    setTimeout(function() { button.textContent = 'Copy'; }, 2500);
  });
});
