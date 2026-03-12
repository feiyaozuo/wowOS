(function () {
  var token = localStorage.getItem('wowos_token') || '';
  var allItems = [];

  function authHeaders() {
    return token ? { 'Authorization': 'Bearer ' + token } : {};
  }

  function api(path, options) {
    options = options || {};
    options.headers = Object.assign({}, options.headers || {}, authHeaders());
    return fetch('/api/proxy/' + path, options).then(function (r) {
      if (r.status >= 400) return Promise.reject(new Error(r.status + ' ' + r.statusText));
      var ct = r.headers.get('Content-Type') || '';
      if (ct.indexOf('application/json') !== -1) return r.json();
      return r.blob();
    });
  }

  function renderList(items) {
    var filter = (document.getElementById('filterName') || {}).value || '';
    var list = items.filter(function (f) {
      var name = (f.name || f.file_id || '').toLowerCase();
      return !filter || name.indexOf(filter.toLowerCase()) !== -1;
    });
    var tbody = document.getElementById('list');
    if (!list.length) {
      tbody.innerHTML = '<tr><td colspan="6">No files. Set token in Settings and upload a file.</td></tr>';
      return;
    }
    tbody.innerHTML = list.map(function (f) {
      var level = f.privacy_level ?? f.level ?? 3;
      var tags = Array.isArray(f.tags) ? f.tags.join(', ') : (f.tags || '');
      var created = f.created_at ? new Date(f.created_at * 1000).toLocaleString() : '';
      var size = f.size != null ? (f.size < 1024 ? f.size + ' B' : (f.size < 1024 * 1024 ? (f.size / 1024).toFixed(1) + ' KB' : (f.size / 1024 / 1024).toFixed(1) + ' MB')) : '';
      return '<tr>' +
        '<td>' + (f.name || f.file_id) + '</td>' +
        '<td><span class="level level-' + level + '">L' + level + '</span></td>' +
        '<td>' + tags + '</td>' +
        '<td>' + size + '</td>' +
        '<td>' + created + '</td>' +
        '<td class="act">' +
          '<a href="#" data-action="detail" data-id="' + f.file_id + '">Detail</a> ' +
          '<a href="#" data-action="download" data-id="' + f.file_id + '" data-name="' + (f.name || f.file_id) + '">Download</a> ' +
          '<button type="button" data-action="delete" data-id="' + f.file_id + '">Delete</button>' +
        '</td></tr>';
    }).join('');
    tbody.querySelectorAll('[data-action]').forEach(function (el) {
      el.addEventListener('click', function (e) {
        e.preventDefault();
        var action = el.getAttribute('data-action');
        var id = el.getAttribute('data-id');
        var name = el.getAttribute('data-name');
        if (action === 'detail') showDetail(id);
        else if (action === 'download') downloadFile(id, name);
        else if (action === 'delete') deleteFile(id);
      });
    });
  }

  function loadFiles() {
    if (!token) {
      document.getElementById('list').innerHTML = '<tr><td colspan="6">Set token in Settings to list files.</td></tr>';
      document.getElementById('err').style.display = 'block';
      document.getElementById('err').textContent = 'No token. Go to Settings to set your API token.';
      return;
    }
    document.getElementById('err').style.display = 'none';
    api('files').then(function (d) {
      allItems = d.items || [];
      renderList(allItems);
    }).catch(function (e) {
      document.getElementById('err').style.display = 'block';
      document.getElementById('err').textContent = 'List failed: ' + e.message;
      document.getElementById('list').innerHTML = '';
    });
  }

  function showDetail(fileId) {
    api('files/' + fileId + '/meta').then(function (meta) {
      document.getElementById('detailTitle').textContent = meta.name || meta.file_id;
      var dl = document.getElementById('detailBody');
      var rows = [
        ['File ID', meta.file_id],
        ['Name', meta.name],
        ['Level', 'L' + (meta.privacy_level ?? meta.level ?? 3)],
        ['Tags', Array.isArray(meta.tags) ? meta.tags.join(', ') : (meta.tags || '-')],
        ['Category', meta.category || '-'],
        ['Size', meta.size != null ? meta.size + ' bytes' : '-'],
        ['Created', meta.created_at ? new Date(meta.created_at * 1000).toLocaleString() : '-'],
        ['Updated', meta.updated_at ? new Date(meta.updated_at * 1000).toLocaleString() : '-'],
      ];
      dl.innerHTML = rows.map(function (r) { return '<dt>' + r[0] + '</dt><dd>' + r[1] + '</dd>'; }).join('');
      document.getElementById('detailModal').classList.add('show');
    }).catch(function (e) {
      alert('Detail failed: ' + e.message);
    });
  }

  function downloadFile(fileId, name) {
    if (!token) { alert('Set token in Settings.'); return; }
    fetch('/api/proxy/files/' + fileId, { headers: authHeaders() }).then(function (r) {
      if (!r.ok) return Promise.reject(new Error(r.status));
      return r.blob();
    }).then(function (blob) {
      var a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      a.download = name || fileId;
      a.click();
      URL.revokeObjectURL(a.href);
    }).catch(function (e) {
      alert('Download failed: ' + e.message);
    });
  }

  function deleteFile(fileId) {
    if (!confirm('Delete this file?')) return;
    if (!token) { alert('Set token in Settings.'); return; }
    fetch('/api/proxy/files/' + fileId, { method: 'DELETE', headers: authHeaders() }).then(function (r) {
      if (!r.ok) return Promise.reject(new Error(r.status));
      loadFiles();
    }).catch(function (e) {
      alert('Delete failed: ' + e.message);
    });
  }

  document.getElementById('detailClose').addEventListener('click', function () {
    document.getElementById('detailModal').classList.remove('show');
  });
  document.getElementById('detailModal').addEventListener('click', function (e) {
    if (e.target === this) this.classList.remove('show');
  });

  document.getElementById('uploadForm').addEventListener('submit', function (e) {
    e.preventDefault();
    var fileInput = document.getElementById('fileInput');
    var file = fileInput && fileInput.files[0];
    if (!file) return;
    var formData = new FormData();
    formData.append('file', file);
    formData.append('privacy_level', document.getElementById('uploadLevel').value);
    var errEl = document.getElementById('uploadErr');
    errEl.style.display = 'none';
    fetch('/api/proxy/files', {
      method: 'POST',
      headers: authHeaders(),
      body: formData
    }).then(function (r) {
      if (!r.ok) return Promise.reject(new Error(r.status + ' ' + r.statusText));
      return r.json();
    }).then(function () {
      fileInput.value = '';
      loadFiles();
    }).catch(function (e) {
      errEl.style.display = 'block';
      errEl.textContent = 'Upload failed: ' + e.message;
    });
  });

  document.getElementById('filterName').addEventListener('input', function () {
    renderList(allItems);
  });

  token = localStorage.getItem('wowos_token') || '';
  loadFiles();
})();
