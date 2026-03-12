(function () {
  var STORAGE_URL = 'wowos_ha_url';
  var STORAGE_TOKEN = 'wowos_ha_token';

  function getUrl() { return localStorage.getItem(STORAGE_URL) || ''; }
  function getToken() { return localStorage.getItem(STORAGE_TOKEN) || ''; }
  function setUrl(v) { localStorage.setItem(STORAGE_URL, v); }
  function setToken(v) { localStorage.setItem(STORAGE_TOKEN, v); }

  function api(path, body) {
    var opts = { method: 'POST', headers: { 'Content-Type': 'application/json' } };
    if (body) opts.body = JSON.stringify(body);
    return fetch('/api/proxy/' + path, opts).then(function (r) {
      if (!r.ok) return Promise.reject(new Error(r.status + ' ' + r.statusText));
      return r.json();
    });
  }

  document.getElementById('haUrl').value = getUrl();
  document.getElementById('haToken').value = getToken();

  document.getElementById('haUrl').addEventListener('change', function () { setUrl(this.value); });
  document.getElementById('haToken').addEventListener('change', function () { setToken(this.value); });

  document.getElementById('btnConnect').addEventListener('click', function () {
    var url = document.getElementById('haUrl').value.trim().replace(/\/$/, '');
    var token = document.getElementById('haToken').value.trim();
    setUrl(url);
    setToken(token);
    var result = document.getElementById('connectResult');
    result.textContent = '…';
    result.className = '';
    if (!url || !token) {
      result.textContent = 'Enter URL and token.';
      result.className = 'err';
      return;
    }
    api('homeassistant/connect', { base_url: url, token: token })
      .then(function (d) {
        result.textContent = d.connected ? 'Connected.' : 'Connection failed.';
        result.className = d.connected ? 'ok' : 'err';
      })
      .catch(function (e) {
        result.textContent = 'Error: ' + e.message;
        result.className = 'err';
      });
  });

  document.getElementById('btnLoad').addEventListener('click', function () {
    var url = document.getElementById('haUrl').value.trim().replace(/\/$/, '');
    var token = document.getElementById('haToken').value.trim();
    if (!url || !token) {
      alert('Enter URL and token first.');
      return;
    }
    var list = document.getElementById('entityList');
    list.innerHTML = '<li>Loading…</li>';
    api('homeassistant/entities', { base_url: url, token: token })
      .then(function (d) {
        var entities = d.entities || [];
        if (!entities.length) {
          list.innerHTML = '<li>No entities.</li>';
          return;
        }
        list.innerHTML = entities.map(function (e) {
          var id = e.entity_id || '';
          var name = e.attributes && e.attributes.friendly_name ? e.attributes.friendly_name : id;
          var state = e.state || 'unknown';
          var domain = id.split('.')[0] || 'light';
          var canToggle = (domain === 'light' || domain === 'switch') && state !== 'unavailable';
          var toggleLabel = state === 'on' ? 'Off' : 'On';
          var action = state === 'on' ? 'turn_off' : 'turn_on';
          var btn = canToggle
            ? '<button data-id="' + id + '" data-action="' + action + '">' + toggleLabel + '</button>'
            : '';
          return '<li><span>' + name + ' <span class="state">(' + id + ') ' + state + '</span></span> ' + btn + '</li>';
        }).join('');
        list.querySelectorAll('button').forEach(function (btn) {
          btn.addEventListener('click', function () {
            var id = btn.getAttribute('data-id');
            var action = btn.getAttribute('data-action');
            api('homeassistant/control', { base_url: url, token: token, entity_id: id, action: action })
              .then(function () { document.getElementById('btnLoad').click(); })
              .catch(function (err) { alert('Control failed: ' + err.message); });
          });
        });
      })
      .catch(function (e) {
        list.innerHTML = '<li class="err">Load failed: ' + e.message + '</li>';
      });
  });
})();
