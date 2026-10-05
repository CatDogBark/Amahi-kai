// File Browser Controller
//
// The web file browser only views: files are added, renamed and deleted over the SMB shares,
// so Samba (and Greyhole on pooled shares) sees every change. This previews images, video,
// audio and PDFs in a dialog.

(function() {
  var FileBrowserController = class extends Stimulus.Controller {
    static get targets() {
      return ["previewModal", "previewTitle", "previewBody", "previewDownload"];
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
      }

      var modal = new bootstrap.Modal(this.previewModalTarget);
      modal.show();
    }
  };


  registerStimulusController("file-browser", FileBrowserController);
})();
