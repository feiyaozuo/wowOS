# wowOS Desktop Plan (from 桌面化改造任务书 v1)

## Delivered

### A. Graphical desktop boot
- **First-boot oneshot** (`wowos-install-desktop-once.service`): installs `raspberrypi-ui-mods`, `chromium`, `unclutter`; sets `graphical.target` as default; installs autostart entry for wowOS Launcher.
- **Autostart**: `/etc/xdg/autostart/wowos-launcher.desktop` runs Chromium in kiosk to `http://localhost:9090/` when a user logs in.
- **Result**: After first boot (and optional reboot), system boots to graphical target; after login, wowOS Home opens in kiosk.

### B. wowOS Launcher / Home
- **Desktop server** (`ui/desktop_server.py`): Flask app on port 9090; serves `/` (launcher), `/app-center`, `/file-center`, `/settings`; proxies `/api/proxy/*` → wowOS API (8080), `/api/app-center/*` → App Center (8000).
- **Launcher** (`ui/launcher/index.html`): Home with three entries (App Center, File Center, Settings); shows API connection status.

### C. Three GUI MVPs
- **App Center** (`ui/app_center_ui/index.html`): Lists available apps from App Center (`/api/app-center/apps.json`); placeholder for installed list.
- **File Center** (`ui/file_center_ui/index.html`): Lists files via `GET /api/proxy/files` (requires token set in Settings).
- **Settings** (`ui/settings_ui/index.html`): API health, API token input (saved to localStorage), device/UA info.

### D. Desktop ↔ API
- **Proxy**: All UI calls go to same origin (9090); desktop server proxies to 8080 and 8000 (no CORS).
- **Real data**: Health from `/api/v1/health`; file list from new `GET /api/v1/files` (token required); app list from App Center.

## Build / deploy

- **Image**: All four build scripts copy `ui/` to `/opt/wowos/ui` and install `wowos-desktop.service` (enabled at boot).
- **First boot**: Desktop install runs once; then reboot to enter graphical and get launcher on login.
- **Manual (existing Pi)**: Copy `ui/` and `services/wowos-desktop.service`; enable and start `wowos-desktop`; run first-boot desktop script once; reboot.

## URLs

- Launcher: `http://localhost:9090/`
- App Center UI: `http://localhost:9090/app-center`
- File Center UI: `http://localhost:9090/file-center`
- Settings: `http://localhost:9090/settings`

## Lightdm / Xorg issues (task book A)

If the device still shows black screen or “no screens found”, fix on the Pi:

- Check `/var/log/lightdm/`, `/var/log/Xorg.0.log`.
- Ensure `/boot/firmware/config.txt` has `dtoverlay=vc4-kms-v3d` and no conflicting display options.
- Consider switching display manager or session type per task book A-4.
