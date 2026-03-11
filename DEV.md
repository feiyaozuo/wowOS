# wowOS Development and Run

## Local run (no Pi required)

### 1. Install dependencies

```bash
pip3 install -r requirements.txt
```

### 2. Start system API

```bash
python3 run_api.py
# Default http://localhost:8080
```

### 3. Get token and test

```bash
# Issue token (requires admin token in production; set WOWOS_DEV_MODE=1 and WOWOS_ADMIN_TOKEN for dev)
curl -X POST http://localhost:8080/api/v1/tokens \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN" \
  -d '{"app_id":"test","user_id":"u1","resources":["file/*"],"max_level":3,"ttl":3600}'

# Upload file (replace TOKEN with the token from above)
curl -X POST http://localhost:8080/api/v1/files \
  -H "Authorization: Bearer TOKEN" \
  -F "file=@/path/to/file" -F "privacy_level=3"

# Download file
curl -H "Authorization: Bearer TOKEN" "http://localhost:8080/api/v1/files/FILE_ID" -o out
```

### 4. Develop apps with mock_os

```bash
# Terminal 1: start mock service
python3 run_mock_os.py
# Default http://localhost:8081

# Terminal 2: run Family Ledger in mock mode
export WOWOS_MOCK=1
cd apps/family-ledger && python3 app.py
# Open http://localhost:5001
```

### 5. App center and packaging

- Package apps as `.wapp` (tar.gz with manifest.json etc.) and put under `app_center/packages/`
- Generate index: `cd app_center && python3 generate_index.py`
- Serve static: `cd app_center && python3 -m http.server 8000`
- App management: use `AppManager` in `apps/app_manager.py` to install/uninstall (configure app center URL).

### 6. Data directories

- Dev default: project `data/` (audit DB, revocation list, file storage, app DB, etc.)
- Override with env: `VAR_LIB_WOWOS`, `WOWOS_DATA_PATH`, `WOWOS_AUDIT_DB`, etc.
