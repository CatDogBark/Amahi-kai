// Apps plugin JS

// POST action for docker app controls (start/stop/uninstall)
function dockerAppAction(url) {
  fetch(url, {
    method: 'POST',
    headers: csrfHeaders(),
    credentials: 'same-origin'
  })
    .then(function(response) {
      if (response.redirected) {
        window.location.href = response.url;
      } else {
        window.location.reload();
      }
    })
    .catch(function(err) {
      console.error('App action failed:', err);
      window.location.reload();
    });
}
