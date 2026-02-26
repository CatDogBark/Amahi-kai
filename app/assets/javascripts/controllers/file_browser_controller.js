// File Browser Controller
//
// Handles uploads, drag-and-drop, file actions, preview, and selection.

(function() {
  var FileBrowserController = class extends Stimulus.Controller {
    static get targets() {
      return ["fileInput", "dropzone", "dropOverlay", "bulkDelete", "selectAll",
              "previewModal", "previewTitle", "previewBody", "previewDownload"];
    }
    static get values() {
      return {
        share: String,
        path: String,
        uploadUrl: String,
        newFolderUrl: String,
        renameUrl: String,
        deleteUrl: String
      };
    }

    // ── Selection ──

    toggleAll(event) {
      var checked = event.currentTarget.checked;
      this.element.querySelectorAll('.fb-item-check').forEach(function(cb) {
        cb.checked = checked;
      });
      this.updateBulkActions();
    }

    updateSelection() {
      this.updateBulkActions();
    }

    updateBulkActions() {
      var selected = this.selectedNames();
      if (this.hasBulkDeleteTarget) {
        if (selected.length > 0) {
          this.bulkDeleteTarget.classList.remove('d-none');
          this.bulkDeleteTarget.textContent = '🗑️ Delete ' + selected.length + ' selected';
        } else {
          this.bulkDeleteTarget.classList.add('d-none');
        }
      }
    }

    selectedNames() {
      var names = [];
      this.element.querySelectorAll('.fb-item-check:checked').forEach(function(cb) {
        names.push(cb.value);
      });
      return names;
    }

    // ── Upload ──

    uploadFiles(event) {
      var files = event.currentTarget.files;
      if (files.length > 0) this.doUpload(files);
    }

    doUpload(files) {
      var _this = this;
      var formData = new FormData();
      for (var i = 0; i < files.length; i++) {
        formData.append('files[]', files[i]);
      }
      formData.append('path', this.pathValue);

      var btn = this.element.querySelector('[title="Upload Files"]');
      if (btn) {
        btn.dataset.originalText = btn.innerHTML;
        btn.innerHTML = '<span class="spinner-border spinner-border-sm"></span> Uploading...';
        btn.style.pointerEvents = 'none';
      }

      fetch(this.uploadUrlValue + '?path=' + encodeURIComponent(this.pathValue), {
        method: 'POST',
        headers: csrfHeaders(),
        body: formData,
        credentials: 'same-origin'
      })
      .then(function(r) { return r.json(); })
      .then(function(data) {
        if (data.status === 'ok') {
          showToast('Uploaded ' + data.count + ' file(s)', 'success');
          window.location.reload();
        } else {
          showToast(data.error || 'Upload failed', 'error');
        }
      })
      .catch(function(err) {
        console.error('Upload failed:', err);
        showToast('Upload failed', 'error');
      })
      .finally(function() {
        if (btn) {
          btn.innerHTML = btn.dataset.originalText;
          btn.style.pointerEvents = '';
        }
      });
    }

    // ── Drag and Drop ──

    dragOver(event) {
      event.preventDefault();
      event.dataTransfer.dropEffect = 'copy';
    }

    dragEnter(event) {
      event.preventDefault();
      if (this.hasDropOverlayTarget) {
        this.dropOverlayTarget.classList.add('fb-drop-active');
      }
    }

    dragLeave(event) {
      // Only hide if leaving the dropzone entirely
      if (!this.dropzoneTarget.contains(event.relatedTarget)) {
        if (this.hasDropOverlayTarget) {
          this.dropOverlayTarget.classList.remove('fb-drop-active');
        }
      }
    }

    drop(event) {
      event.preventDefault();
      if (this.hasDropOverlayTarget) {
        this.dropOverlayTarget.classList.remove('fb-drop-active');
      }
      var files = event.dataTransfer.files;
      if (files.length > 0) this.doUpload(files);
    }

    // ── New Folder ──

    newFolder() {
      var name = prompt('Folder name:');
      if (!name || !name.trim()) return;

      fetch(this.newFolderUrlValue + '?path=' + encodeURIComponent(this.pathValue), {
        method: 'POST',
        headers: Object.assign({ 'Content-Type': 'application/json' }, csrfHeaders()),
        body: JSON.stringify({ name: name.trim(), path: this.pathValue }),
        credentials: 'same-origin'
      })
      .then(function(r) { return r.json(); })
      .then(function(data) {
        if (data.status === 'ok') {
          showToast('Created folder: ' + data.name, 'success');
          window.location.reload();
        } else {
          showToast(data.error || 'Failed to create folder', 'error');
        }
      })
      .catch(function(err) {
        console.error('New folder failed:', err);
        showToast('Failed to create folder', 'error');
      });
    }

    // ── Rename ──

    renameItem(event) {
      event.preventDefault();
      var oldName = event.currentTarget.dataset.name;
      var newName = prompt('New name:', oldName);
      if (!newName || !newName.trim() || newName === oldName) return;

      fetch(this.renameUrlValue + '?path=' + encodeURIComponent(this.pathValue), {
        method: 'PUT',
        headers: Object.assign({ 'Content-Type': 'application/json' }, csrfHeaders()),
        body: JSON.stringify({ old_name: oldName, new_name: newName.trim(), path: this.pathValue }),
        credentials: 'same-origin'
      })
      .then(function(r) { return r.json(); })
      .then(function(data) {
        if (data.status === 'ok') {
          showToast('Renamed to: ' + data.new_name, 'success');
          window.location.reload();
        } else {
          showToast(data.error || 'Rename failed', 'error');
        }
      })
      .catch(function(err) {
        console.error('Rename failed:', err);
        showToast('Rename failed', 'error');
      });
    }

    // ── Delete ──

    deleteItem(event) {
      event.preventDefault();
      var name = event.currentTarget.dataset.name;
      if (!confirm('Delete "' + name + '"?')) return;
      this.doDelete([name]);
    }

    bulkDelete() {
      var names = this.selectedNames();
      if (names.length === 0) return;
      if (!confirm('Delete ' + names.length + ' item(s)?')) return;
      this.doDelete(names);
    }

    doDelete(names) {
      fetch(this.deleteUrlValue + '?path=' + encodeURIComponent(this.pathValue), {
        method: 'DELETE',
        headers: Object.assign({ 'Content-Type': 'application/json' }, csrfHeaders()),
        body: JSON.stringify({ names: names, path: this.pathValue }),
        credentials: 'same-origin'
      })
      .then(function(r) { return r.json(); })
      .then(function(data) {
        if (data.status === 'ok') {
          showToast('Deleted ' + data.count + ' item(s)', 'success');
          window.location.reload();
        } else {
          showToast(data.error || 'Delete failed', 'error');
        }
      })
      .catch(function(err) {
        console.error('Delete failed:', err);
        showToast('Delete failed', 'error');
      });
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
