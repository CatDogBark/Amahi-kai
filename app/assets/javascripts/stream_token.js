// Progress streams (EventSource) must be GET, so they carry the page's CSRF token
// in the URL; the server refuses a stream without it. Sec-Fetch-Site would also
// do, but browsers only send it over HTTPS, and the LAN UI is plain HTTP.
function withStreamToken(url) {
  var meta = document.querySelector('meta[name="csrf-token"]');
  if (!meta) return url;
  return url + (url.indexOf('?') === -1 ? '?' : '&') +
    'authenticity_token=' + encodeURIComponent(meta.content);
}
