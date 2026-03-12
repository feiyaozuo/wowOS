(function () {
  var token = localStorage.getItem('wowos_token') || '';

  function authHeaders() {
    return token ? { 'Authorization': 'Bearer ' + token } : {};
  }

  function api(path, body) {
    var opts = { method: body ? 'POST' : 'GET', headers: { 'Content-Type': 'application/json' } };
    Object.assign(opts.headers, authHeaders());
    if (body) opts.body = JSON.stringify(body);
    return fetch('/api/proxy/' + path, opts).then(function (r) {
      if (!r.ok) return Promise.reject(new Error(r.status + ' ' + r.statusText));
      return r.json();
    });
  }

  function loadProviders() {
    api('llm/providers').then(function (d) {
      var sel = document.getElementById('providerId');
      sel.innerHTML = '<option value="">-- Select --</option>' + (d.providers || []).map(function (p) {
        return '<option value="' + p.id + '">' + (p.name || p.id) + '</option>';
      }).join('');
    }).catch(function () {});
  }

  function loadFiles() {
    if (!token) return;
    api('files').then(function (d) {
      var sel = document.getElementById('fileId');
      var items = d.items || [];
      sel.innerHTML = '<option value="">-- Select file --</option>' + items.map(function (f) {
        return '<option value="' + f.file_id + '">' + (f.name || f.file_id) + '</option>';
      }).join('');
    }).catch(function () {});
  }

  document.getElementById('btnSend').addEventListener('click', function () {
    var fileId = document.getElementById('fileId').value;
    var providerId = document.getElementById('providerId').value;
    var redactFirst = document.getElementById('redactFirst').checked;
    var prompt = document.getElementById('prompt').value.trim() || 'Summarize the following content.';
    var errEl = document.getElementById('sendErr');
    var resultEl = document.getElementById('result');
    errEl.style.display = 'none';
    resultEl.style.display = 'none';
    if (!token) {
      errEl.textContent = 'Set token in Settings.';
      errEl.style.display = 'block';
      return;
    }
    if (!fileId || !providerId) {
      errEl.textContent = 'Select a file and a provider.';
      errEl.style.display = 'block';
      return;
    }
    resultEl.textContent = 'Sending…';
    resultEl.style.display = 'block';
    api('llm/analyze', { file_id: fileId, provider_id: providerId, redact_first: redactFirst, prompt: prompt })
      .then(function (d) {
        resultEl.textContent = d.content || '(empty response)';
        document.getElementById('btnHistory').click();
      })
      .catch(function (e) {
        errEl.textContent = 'Error: ' + e.message;
        errEl.style.display = 'block';
        resultEl.style.display = 'none';
      });
  });

  document.getElementById('btnHistory').addEventListener('click', function () {
    if (!token) return;
    api('llm/history').then(function (d) {
      var list = document.getElementById('historyList');
      var items = d.items || [];
      if (!items.length) {
        list.innerHTML = '<li>No history.</li>';
        return;
      }
      list.innerHTML = items.map(function (h) {
        var ts = h.timestamp ? new Date(h.timestamp * 1000).toLocaleString() : '';
        var res = h.result || '';
        return '<li>' + ts + ' – ' + (h.resource || '') + ' – ' + res + '</li>';
      }).join('');
    }).catch(function () {
      document.getElementById('historyList').innerHTML = '<li class="err">Load failed.</li>';
    });
  });

  token = localStorage.getItem('wowos_token') || '';
  loadProviders();
  loadFiles();
})();
