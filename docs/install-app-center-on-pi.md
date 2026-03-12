# Install App Center on Raspberry Pi

App Center serves `apps.json` and `.wapp` packages so that wowOS can install apps via AppManager.

## 1. Copy app_center to the Pi

On your **Mac** (project root):

```bash
cd /path/to/wowOS
scp -r app_center admin@192.168.2.37:~/
```

SSH to the Pi and move it under `/opt/wowos`:

```bash
ssh admin@192.168.2.37
sudo mkdir -p /opt/wowos
sudo mv ~/app_center /opt/wowos/
sudo chown -R root:root /opt/wowos/app_center
```

## 2. Add packages and generate index

On the **Pi**:

```bash
# Create packages dir if missing
sudo mkdir -p /opt/wowos/app_center/packages

# If you have .wapp files, copy them to /opt/wowos/app_center/packages/
# Then generate apps.json (replace 192.168.2.37 with your Pi's IP)
cd /opt/wowos/app_center
sudo WOWOS_APP_CENTER_BASE_URL=http://192.168.2.37:8000 python3 generate_index.py
```

To build the Family Ledger .wapp on your Mac and copy to Pi:

```bash
# On Mac: create .wapp (tar root = app contents so manifest.json is at install root)
cd /path/to/wowOS
tar -czvf app_center/packages/com.wowos.family-ledger.wapp -C apps/family-ledger .

# Regenerate index on Mac (or after copying to Pi, run generate_index.py on Pi)
cd app_center && python3 generate_index.py

# Copy to Pi
scp app_center/packages/com.wowos.family-ledger.wapp admin@192.168.2.37:~/
# On Pi: sudo mv ~/com.wowos.family-ledger.wapp /opt/wowos/app_center/packages/
# On Pi: cd /opt/wowos/app_center && sudo WOWOS_APP_CENTER_BASE_URL=http://192.168.2.37:8000 python3 generate_index.py
```

## 3. Install and start the service

Copy the systemd unit to the Pi (on **Mac**):

```bash
scp services/wowos-app-center.service admin@192.168.2.37:~/
```

On the **Pi**:

```bash
sudo mv ~/wowos-app-center.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable wowos-app-center
sudo systemctl start wowos-app-center
sudo systemctl status wowos-app-center
```

## 4. Verify

- Open in browser: `http://192.168.2.37:8000/apps.json` — should show `{"apps":[...]}`.
- Open: `http://192.168.2.37:8000/` — simple directory listing.

## 5. Point AppManager at this app center

When installing apps (e.g. via API or a future admin UI), set the app center URL to the Pi itself:

```bash
# Optional: set env for any process that runs AppManager
export WOWOS_APP_CENTER_URL=http://192.168.2.37:8000
```

Default in code is `http://app-center.local:8000`; if you don't use that hostname, override with `WOWOS_APP_CENTER_URL` when calling AppManager.
