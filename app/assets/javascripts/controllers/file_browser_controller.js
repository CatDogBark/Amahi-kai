// File Browser Controller
//
// The web file browser only views: files are added, renamed and deleted over the SMB shares,
// so Samba (and Greyhole on pooled shares) sees every change. A row is one link: a folder opens
// (the link's own job), a file is shown in the panel beside the list (select; clicking it again
// closes it), with Download and, for pictures, video, audio, PDFs and text, Open full screen. The
// list can be a grid of tiles
// (setView, remembered in this browser), and a folder's zip says it's coming until its download
// starts (downloadZip).

(function() {
  var VIEW_KEY = 'amahi-kai.fileBrowserView';
  var PREVIEWS = ['image', 'video', 'audio', 'pdf', 'text'];

  function svgIcon(paths) {
    var ns = 'http://www.w3.org/2000/svg';
    var svg = document.createElementNS(ns, 'svg');
    ['width', 'height'].forEach(function(a) { svg.setAttribute(a, '44'); });
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('fill', 'none');
    svg.setAttribute('stroke', 'currentColor');
    svg.setAttribute('stroke-width', '1.6');
    svg.setAttribute('stroke-linecap', 'round');
    svg.setAttribute('stroke-linejoin', 'round');
    paths.forEach(function(d) {
      var p = document.createElementNS(ns, 'path');
      p.setAttribute('d', d);
      svg.appendChild(p);
    });
    return svg;
  }

  function el(tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
  }

  var FileBrowserController = class extends Stimulus.Controller {
    static get targets() {
      return ["previewModal", "previewTitle", "previewBody", "previewDownload", "downloadStatus", "listing", "details"];
    }

    connect() {
      var view = 'list';
      try { view = localStorage.getItem(VIEW_KEY) || 'list'; } catch (e) { /* no storage: the list */ }
      this.applyView(view);
      // What the panel says with no file selected, put back when one is closed
      if (this.hasDetailsTarget) this.emptyDetails = this.detailsTarget.querySelector('.fb-details-empty');
    }

    // ── List or grid ──

    setView(event) {
      var view = event.currentTarget.dataset.view;
      try { localStorage.setItem(VIEW_KEY, view); } catch (e) { /* kept for this page only */ }
      this.applyView(view);
    }

    applyView(view) {
      if (!this.hasListingTarget) return;
      var grid = view === 'grid';
      this.listingTarget.classList.toggle('fb-grid', grid);
      this.element.querySelectorAll('.fb-viewbtn').forEach(function(btn) {
        btn.setAttribute('aria-pressed', String(btn.dataset.view === view));
      });
      // Pictures show as themselves in the grid (loaded only once it's shown)
      if (grid) {
        this.listingTarget.querySelectorAll('.fb-file-link[data-kind="image"]').forEach(function(link) {
          var icon = link.querySelector('.fb-item-icon');
          if (!icon || icon.querySelector('img')) return;
          var img = document.createElement('img');
          img.loading = 'lazy';
          img.alt = '';
          img.src = link.dataset.rawUrl;
          icon.appendChild(img);
        });
      }
    }

    // ── A file, in the panel ──

    select(event) {
      if (!this.hasDetailsTarget) return; // no panel: the link opens the file
      event.preventDefault();
      var link = event.currentTarget;
      var item = link.closest('.fb-item');
      if (item.classList.contains('selected')) { this.deselect(); return; }
      this.element.querySelectorAll('.fb-item.selected').forEach(function(row) { row.classList.remove('selected'); });
      item.classList.add('selected');
      this.selected = link.dataset;

      var d = link.dataset;
      var panel = this.detailsTarget;
      panel.replaceChildren();

      var preview = el('div', 'fb-details-preview');
      if (d.kind === 'image') {
        var img = document.createElement('img');
        img.src = d.rawUrl;
        img.alt = d.name;
        preview.appendChild(img);
      } else if (d.kind === 'video') {
        var video = document.createElement('video');
        video.src = d.rawUrl;
        video.controls = true;
        video.preload = 'metadata';
        preview.appendChild(video);
      } else if (d.kind === 'audio') {
        var audio = document.createElement('audio');
        audio.src = d.rawUrl;
        audio.controls = true;
        preview.appendChild(audio);
      } else {
        preview.classList.add('fb-details-none');
        preview.appendChild(svgIcon(['M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z', 'M14 2v4a2 2 0 0 0 2 2h4']));
        preview.appendChild(el('span', null, PREVIEWS.indexOf(d.kind) !== -1
          ? 'Open it full screen to read it.'
          : 'There\'s no preview for this kind of file. Download it to open it on your computer.'));
      }
      panel.appendChild(preview);

      panel.appendChild(el('div', 'fb-details-name', d.name));
      panel.appendChild(el('div', 'fb-details-kind', d.kindName));

      var facts = el('dl', 'fb-details-facts');
      [['Size', d.size], ['Modified', d.modified]].forEach(function(pair) {
        if (!pair[1]) return;
        facts.appendChild(el('dt', null, pair[0]));
        facts.appendChild(el('dd', null, pair[1]));
      });
      panel.appendChild(facts);

      var actions = el('div', 'fb-details-actions');
      var download = el('a', 'btn btn-info', 'Download');
      download.href = d.downloadUrl;
      actions.appendChild(download);
      if (PREVIEWS.indexOf(d.kind) !== -1) {
        var open = el('button', 'btn btn-outline-info', 'Open full screen');
        open.type = 'button';
        open.addEventListener('click', this.openFull.bind(this));
        actions.appendChild(open);
      }
      panel.appendChild(actions);
    }

    // Closes the selected file's panel (a playing video or song stops with it).
    deselect() {
      this.element.querySelectorAll('.fb-item.selected').forEach(function(row) { row.classList.remove('selected'); });
      this.selected = null;
      this.detailsTarget.replaceChildren();
      if (this.emptyDetails) this.detailsTarget.appendChild(this.emptyDetails);
    }

    // The selected file in the full-screen dialog; text opens in its own tab.
    openFull() {
      var d = this.selected;
      if (!d) return;
      if (d.kind === 'text') { window.open(d.rawUrl, '_blank', 'noopener'); return; }
      if (this.hasPreviewTitleTarget) this.previewTitleTarget.textContent = d.name;
      if (this.hasPreviewDownloadTarget) this.previewDownloadTarget.href = d.downloadUrl;
      var body = this.previewBodyTarget;
      body.replaceChildren();
      var media;
      if (d.kind === 'image') {
        media = document.createElement('img');
        media.alt = d.name;
      } else if (d.kind === 'video') {
        media = document.createElement('video');
        media.controls = true;
      } else if (d.kind === 'audio') {
        media = document.createElement('audio');
        media.controls = true;
      } else if (d.kind === 'pdf') {
        media = document.createElement('iframe');
        media.title = d.name;
      }
      if (!media) return;
      media.src = d.rawUrl;
      media.className = 'fb-modal-media fb-modal-' + d.kind;
      body.appendChild(media);
      new bootstrap.Modal(this.previewModalTarget).show();
    }

    // ── Folder downloads ──

    // The zip is made as it's sent, so its download starts within moments; until then the
    // page says it's coming. The server returns the link's token in the fb_download cookie
    // when it starts sending.
    downloadZip(event) {
      var link = event.currentTarget;
      var token = Math.random().toString(36).slice(2, 12) + Date.now().toString(36);
      var url = new URL(link.href, window.location.href);
      url.searchParams.set('token', token);
      link.href = url.toString(); // the browser follows the link once this returns

      if (!this.hasDownloadStatusTarget) return;
      var status = this.downloadStatusTarget;
      var name = link.dataset.zipName || 'the folder';
      clearInterval(this.downloadTimer);
      status.hidden = false;
      status.className = 'fb-download-status small text-info';
      status.innerHTML = '<span class="spinner-border spinner-border-sm me-1" aria-hidden="true"></span>';
      status.appendChild(document.createTextNode('Starting the download of ' + name + '.zip…'));

      var started = Date.now();
      var self = this;
      this.downloadTimer = setInterval(function() {
        var done = document.cookie.split('; ').indexOf('fb_download=' + token) !== -1;
        if (done) {
          document.cookie = 'fb_download=; path=/; max-age=0';
          status.className = 'fb-download-status small text-muted';
          status.textContent = name + '.zip is downloading: your browser shows its progress.';
        }
        if (done || Date.now() - started > 120000) {
          clearInterval(self.downloadTimer);
          setTimeout(function() { status.hidden = true; }, done ? 6000 : 0);
        }
      }, 400);
    }
  };

  registerStimulusController("file-browser", FileBrowserController);
})();
