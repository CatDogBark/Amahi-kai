// File Browser Controller
//
// The web file browser only views: files are added, renamed and deleted over the SMB shares,
// so Samba (and Greyhole on pooled shares) sees every change. This previews images, video,
// audio and PDFs in a dialog (other files say there's no preview, with Download), and says
// a folder's zip is being made until its download starts.

(function() {
  var FileBrowserController = class extends Stimulus.Controller {
    static get targets() {
      return ["previewModal", "previewTitle", "previewBody", "previewDownload", "downloadStatus"];
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

    // ── Preview ──

    previewFile(event) {
      event.preventDefault();
      var url = event.currentTarget.dataset.previewUrl;
      var mime = event.currentTarget.dataset.previewMime;
      var name = event.currentTarget.dataset.previewName;

      if (this.hasPreviewTitleTarget) this.previewTitleTarget.textContent = name;
      if (this.hasPreviewDownloadTarget) this.previewDownloadTarget.href = url.replace('/raw/', '/download/');

      var body = this.previewBodyTarget;
      body.innerHTML = '';

      if (mime.startsWith('image/')) {
        var img = document.createElement('img');
        img.src = url;
        img.alt = name;
        img.style.cssText = 'max-width:100%;max-height:70vh;border-radius:4px;';
        body.appendChild(img);
      } else if (mime.startsWith('video/')) {
        var video = document.createElement('video');
        video.src = url;
        video.controls = true;
        video.style.cssText = 'max-width:100%;max-height:70vh;';
        body.appendChild(video);
      } else if (mime.startsWith('audio/')) {
        var audio = document.createElement('audio');
        audio.src = url;
        audio.controls = true;
        audio.style.cssText = 'width:100%;margin-top:2rem;';
        body.appendChild(audio);
      } else if (mime === 'application/pdf') {
        var iframe = document.createElement('iframe');
        iframe.src = url;
        iframe.style.cssText = 'width:100%;height:70vh;border:none;border-radius:4px;';
        body.appendChild(iframe);
      } else {
        // A kind of file the browser can't show (an .odt, a .zip...): Download opens it.
        var none = document.createElement('div');
        none.className = 'fb-no-preview py-4';
        var title = document.createElement('p');
        title.className = 'mb-1';
        title.textContent = 'There\'s no preview for this kind of file.';
        var hint = document.createElement('p');
        hint.className = 'small text-muted mb-0';
        var size = event.currentTarget.dataset.previewSize;
        hint.textContent = 'Download it to open it in an app on your computer' + (size ? ' (' + size + ').' : '.');
        none.appendChild(title);
        none.appendChild(hint);
        body.appendChild(none);
      }

      var modal = new bootstrap.Modal(this.previewModalTarget);
      modal.show();
    }
  };


  registerStimulusController("file-browser", FileBrowserController);
})();
