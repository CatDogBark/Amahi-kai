// User Controller
//
// Handles user-specific interactions: delete, toggle admin,
// edit name, update password, update pin.
//
// Mounted on each .user element (whole_user_N)

(function() {
  var UserController = class extends Stimulus.Controller {
    static get targets() {
      return ["deleteArea", "adminCheckbox", "userIcons", "nameDisplay",
              "nameForm", "nameInput", "message", "passwordForm",
              "passwordMessage", "pinForm", "pinMessage"];
    }

    // Delete user
    destroy(event) {
      event.preventDefault();
      var _this = this;
      var url = event.currentTarget.dataset.url;
      var confirmMsg = event.currentTarget.dataset.confirm;

      if (confirmMsg && !confirm(confirmMsg)) return;

      var spinner = event.currentTarget.parentElement.querySelector('.spinner');
      if (spinner) spinner.style.display = '';
      event.currentTarget.style.display = 'none';

      fetch(url, { method: "DELETE", headers: csrfHeaders(), credentials: "same-origin" })
        .then(function(r) { return r.json(); })
        .then(function(data) {
          if (data.status === "ok") {
            _this.element.style.transition = "opacity 0.5s";
            _this.element.style.opacity = "0";
            setTimeout(function() { _this.element.remove(); }, 500);
          } else {
            alert(data.status || "Error");
            if (spinner) spinner.style.display = 'none';
            event.currentTarget.style.display = '';
          }
        })
        .catch(function(err) {
          console.error("Delete failed:", err);
          if (spinner) spinner.style.display = 'none';
          event.currentTarget.style.display = '';
        });
    }

    // Toggle admin checkbox
    toggleAdmin(event) {
      event.preventDefault();
      var _this = this;
      var checkbox = event.currentTarget;
      var url = checkbox.dataset.url;

      var spinner = checkbox.parentElement.querySelector('.spinner');
      if (spinner) spinner.style.display = '';

      fetch(url, { method: "PUT", headers: csrfHeaders(), credentials: "same-origin" })
        .then(function(r) { return r.json(); })
        .then(function(data) {
          if (data.status === "ok") {
            checkbox.checked = !checkbox.checked;
            // Toggle admin icon
            if (_this.hasUserIconsTarget) {
              _this.userIconsTarget.classList.toggle("user_admin");
            }
            // Toggle delete area visibility
            if (_this.hasDeleteAreaTarget) {
              _this.deleteAreaTarget.style.display =
                _this.deleteAreaTarget.style.display === 'none' ? '' : 'none';
            }
          }
        })
        .catch(function(err) { console.error("Toggle admin failed:", err); })
        .finally(function() {
          if (spinner) spinner.style.display = 'none';
        });
    }

    // Show name edit form
    editName(event) {
      event.preventDefault();
      if (this.hasNameDisplayTarget) this.nameDisplayTarget.style.display = 'none';
      if (this.hasNameFormTarget) {
        this.nameFormTarget.style.display = '';
        if (this.hasNameInputTarget) {
          this.nameInputTarget.value = this.nameDisplayTarget.textContent.trim();
          this.nameInputTarget.focus();
        }
      }
    }

    // Cancel name edit
    cancelName(event) {
      event.preventDefault();
      if (this.hasNameFormTarget) this.nameFormTarget.style.display = 'none';
      if (this.hasNameDisplayTarget) this.nameDisplayTarget.style.display = '';
    }

    // Submit name edit
    submitName(event) {
      event.preventDefault();
      var _this = this;
      var form = event.currentTarget;
      var url = form.action;
      var headers = csrfHeaders();
      headers["Content-Type"] = "application/x-www-form-urlencoded; charset=utf-8";
      var body = new URLSearchParams(new FormData(form)).toString();

      fetch(url, { method: "PUT", headers: headers, body: body, credentials: "same-origin" })
        .then(function(r) { return r.json(); })
        .then(function(data) {
          _this.showMessage(_this.messageTarget, data.message);
          if (data.status === "ok" && data.name) {
            if (_this.hasNameDisplayTarget) _this.nameDisplayTarget.textContent = data.name;
            // Update the name in the collapsed row too
            var col2 = _this.element.querySelector('.users-col2');
            if (col2) col2.textContent = data.name;
            _this.cancelName(event);
          }
        })
        .catch(function(err) { console.error("Name update failed:", err); });
    }

    // Submit password form
    submitPassword(event) {
      event.preventDefault();
      var _this = this;
      var form = event.currentTarget;
      var url = form.action;
      var headers = csrfHeaders();
      headers["Content-Type"] = "application/x-www-form-urlencoded; charset=utf-8";
      var body = new URLSearchParams(new FormData(form)).toString();

      fetch(url, { method: "PUT", headers: headers, body: body, credentials: "same-origin" })
        .then(function(r) { return r.json(); })
        .then(function(data) {
          _this.showMessage(_this.passwordMessageTarget, data.message);
          if (data.status === "ok") {
            form.querySelectorAll("input[type=password]").forEach(function(i) { i.value = ""; });
            var edit = form.querySelector('.password-edit');
            if (edit) {
              edit.style.transition = "opacity 0.3s";
              edit.style.opacity = "0";
              setTimeout(function() { edit.style.display = "none"; edit.style.opacity = "1"; }, 300);
            }
          }
        })
        .catch(function(err) { console.error("Password update failed:", err); });
    }

    // Submit pin form
    submitPin(event) {
      event.preventDefault();
      var _this = this;
      var form = event.currentTarget;
      var url = form.action;
      var headers = csrfHeaders();
      headers["Content-Type"] = "application/x-www-form-urlencoded; charset=utf-8";
      var body = new URLSearchParams(new FormData(form)).toString();

      fetch(url, { method: "PUT", headers: headers, body: body, credentials: "same-origin" })
        .then(function(r) { return r.json(); })
        .then(function(data) {
          _this.showMessage(_this.pinMessageTarget, data.message);
          if (data.status === "ok") {
            form.querySelectorAll("input[type=password]").forEach(function(i) { i.value = ""; });
            var edit = form.querySelector('.pin-edit');
            if (edit) {
              edit.style.transition = "opacity 0.3s";
              edit.style.opacity = "0";
              setTimeout(function() { edit.style.display = "none"; edit.style.opacity = "1"; }, 300);
            }
          }
        })
        .catch(function(err) { console.error("Pin update failed:", err); });
    }

    // Helper: show a temporary message
    showMessage(target, text) {
      if (target) {
        target.textContent = text || "";
        setTimeout(function() { target.textContent = ""; }, 8000);
      }
    }
  };

  registerStimulusController("user", UserController);
})();
