#!/usr/bin/env python3
"""Run on Pi to see why install_app returns False. Usage: sudo WOWOS_APP_CENTER_URL=http://IP:8000 python3 debug_install_app.py"""
import sys
sys.path.insert(0, "/opt/wowos")

app_id = "com.wowos.family-ledger"
print("1. Import AppManager...")
try:
    from apps.app_manager import AppManager
except Exception as e:
    print("   FAIL:", e)
    sys.exit(1)
print("   OK")

print("2. AppManager(), get_available_apps()...")
m = AppManager()
apps = m.get_available_apps()
print("   Apps from center:", len(apps), [a.get("id") for a in apps])
app_info = next((a for a in apps if a.get("id") == app_id), None)
if not app_info:
    print("   FAIL: app_id not in list")
    sys.exit(1)
print("   OK")

print("3. download_url, checksum...")
download_url = app_info.get("download_url")
checksum = app_info.get("checksum")
if not download_url:
    print("   FAIL: no download_url")
    sys.exit(1)
print("   OK", download_url[:50], "...")

print("4. Download...")
try:
    import requests
    r = requests.get(download_url, stream=True, timeout=60)
    r.raise_for_status()
    pkg_path = "/tmp/app.wapp"
    with open(pkg_path, "wb") as f:
        for chunk in r.iter_content(chunk_size=8192):
            f.write(chunk)
    print("   OK", open(pkg_path, "rb").seek(0, 2), "bytes")
except Exception as e:
    print("   FAIL:", e)
    sys.exit(1)

print("5. Checksum...")
import hashlib
h = hashlib.sha256()
with open(pkg_path, "rb") as f:
    h.update(f.read())
got = h.hexdigest()
if checksum and got != checksum:
    print("   FAIL: expected", checksum, "got", got)
    sys.exit(1)
print("   OK")

print("6. _ensure_app_user...")
app_user = m._ensure_app_user(app_id)
if not app_user:
    print("   FAIL: could not create/find user")
    sys.exit(1)
print("   OK", app_user)

print("7. _safe_extract_tar...")
import os
from apps.app_manager import APP_DIR
install_path = os.path.join(APP_DIR, app_id)
os.makedirs(install_path, exist_ok=True)
ok = m._safe_extract_tar(pkg_path, install_path)
if not ok:
    print("   FAIL: safe_extract returned False")
    import shutil
    shutil.rmtree(install_path, ignore_errors=True)
    sys.exit(1)
print("   OK")
print("   Contents:", os.listdir(install_path))

print("8. manifest.json exists?")
manifest_path = os.path.join(install_path, "manifest.json")
if not os.path.exists(manifest_path):
    print("   FAIL: no manifest.json at", manifest_path)
    sys.exit(1)
print("   OK")

print("All checks passed. install_app() should succeed; run it again or check chown/systemctl.")
