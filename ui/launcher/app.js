(function () {
  var statusEl = document.getElementById('status');
  if (!statusEl) return;
  fetch('/api/proxy/health')
    .then(function (r) { return r.json(); })
    .then(function (d) {
      statusEl.textContent = d.status === 'ok' ? 'Backend: connected' : 'Backend: unknown';
    })
    .catch(function () {
      statusEl.textContent = 'Backend: not reachable';
    });
})();
