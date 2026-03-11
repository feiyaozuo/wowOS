"""App manager: install/update/uninstall, list installed, talk to app center; generates systemd unit on install."""
import json
import os
import hashlib
import shutil
import sqlite3
import subprocess
import tarfile
from pathlib import Path
from typing import Any, Dict, List, Optional

# Per-app system user prefix; each app gets wowapp-<safe_app_id>
WOWAPP_USER_PREFIX = "wowapp"
DATA_APPS_DIR = os.environ.get("WOWOS_DATA_APPS", "/data/apps")

try:
    import requests
except ImportError:
    requests = None

APP_DIR = os.environ.get("WOWOS_APP_DIR", "/apps")
DB_PATH = os.environ.get(
    "WOWOS_APPS_DB",
    os.path.join(os.environ.get("VAR_LIB_WOWOS", "/var/lib/wowos"), "apps.db"),
)
SYSTEMD_UNIT_TEMPLATE = os.environ.get(
    "WOWOS_SYSTEMD_TEMPLATE",
    "/etc/systemd/system/wowos-app@.service.template",
)
SYSTEMD_UNIT_DIR = "/etc/systemd/system"


def _var_lib() -> str:
    return os.environ.get("VAR_LIB_WOWOS") or os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data"
    )


class AppManager:
    def __init__(self, app_center_url: str = None):
        self.app_center_url = app_center_url or os.environ.get(
            "WOWOS_APP_CENTER_URL", "http://app-center.local:8000"
        )
        self.db_path = DB_PATH
        if not os.path.isabs(self.db_path):
            self.db_path = os.path.join(_var_lib(), "apps.db")
        os.makedirs(os.path.dirname(self.db_path) or ".", exist_ok=True)
        os.makedirs(APP_DIR, exist_ok=True)
        self._init_db()

    def _init_db(self) -> None:
        self.conn = sqlite3.connect(self.db_path)
        self.conn.execute(
            """
            CREATE TABLE IF NOT EXISTS installed_apps (
                app_id TEXT PRIMARY KEY,
                name TEXT,
                version TEXT,
                install_path TEXT,
                status TEXT,
                permissions TEXT,
                port INTEGER
            )
        """
        )
        self.conn.commit()

    @staticmethod
    def _safe_app_id(app_id: str) -> str:
        """Safe id for systemd unit name and system username."""
        return app_id.replace(".", "-").replace("@", "-")

    def _ensure_app_user(self, app_id: str) -> Optional[str]:
        """Ensure system user wowapp-<safe_id> exists; return username or None on failure."""
        safe_id = self._safe_app_id(app_id)
        user = f"{WOWAPP_USER_PREFIX}-{safe_id}"
        try:
            subprocess.run(
                ["id", user],
                check=True,
                capture_output=True,
            )
            return user
        except subprocess.CalledProcessError:
            pass
        try:
            subprocess.run(
                ["useradd", "--system", "--no-create-home", "--shell", "/usr/sbin/nologin", user],
                check=True,
                capture_output=True,
            )
            return user
        except (subprocess.CalledProcessError, FileNotFoundError):
            return None

    def _generate_systemd_unit(self, app_id: str, install_path: str, port: int) -> str:
        """Generate systemd unit content (drop privileges + sandbox); written to /etc/systemd/system/ on install."""
        safe_id = self._safe_app_id(app_id)
        user = f"{WOWAPP_USER_PREFIX}-{safe_id}"
        # Only app dir and optional data dir; do not expose /data/files
        rw_paths = [install_path]
        app_data = os.path.join(DATA_APPS_DIR, app_id)
        if os.path.isdir(app_data):
            rw_paths.append(app_data)
        read_write_paths = " ".join(rw_paths)
        return f"""[Unit]
Description=wowOS App {app_id}
After=network.target wowos-api.service
Requires=wowos-api.service

[Service]
Type=simple
User={user}
Group={user}
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths={read_write_paths}
WorkingDirectory={install_path}
ExecStart=/usr/bin/python3 {install_path}/app.py
Restart=on-failure
RestartSec=10
Environment="PYTHONUNBUFFERED=1"
Environment="WOWOS_API_URL=http://localhost:8080/api/v1"
Environment="WOWOS_APP_PORT={port}"

[Install]
WantedBy=multi-user.target
"""

    def _safe_extract_tar(self, tar_path: str, install_path: str) -> bool:
        """Safely extract .wapp: reject path traversal, absolute paths, symlinks pointing outside."""
        install_path_abs = os.path.abspath(install_path)
        try:
            with tarfile.open(tar_path, "r:gz") as tar:
                for member in tar.getmembers():
                    name = member.name
                    if name.startswith("/") or ".." in name:
                        return False
                    dest = os.path.normpath(os.path.join(install_path, name))
                    if not os.path.abspath(dest).startswith(install_path_abs):
                        return False
                    link_target = getattr(member, "linkname", None)
                    if link_target is not None:
                        if link_target.startswith("/") or ".." in link_target:
                            return False
                        resolved = os.path.normpath(
                            os.path.join(os.path.dirname(dest), link_target)
                        )
                        if not os.path.abspath(resolved).startswith(install_path_abs):
                            return False
                    tar.extract(member, install_path)
        except (tarfile.TarError, OSError):
            return False
        return True

    def _install_systemd_unit(self, app_id: str, install_path: str, port: int) -> bool:
        """Generate and install systemd unit; requires root."""
        content = self._generate_systemd_unit(app_id, install_path, port)
        unit_name = f"wowos-app-{app_id.replace('.', '-')}.service"
        unit_path = os.path.join(SYSTEMD_UNIT_DIR, unit_name)
        try:
            with open(unit_path, "w") as f:
                f.write(content)
            subprocess.run(["systemctl", "daemon-reload"], check=True, capture_output=True)
            subprocess.run(["systemctl", "enable", unit_name], check=True, capture_output=True)
            return True
        except (OSError, subprocess.CalledProcessError):
            return False

    def get_available_apps(self) -> List[Dict[str, Any]]:
        if not requests:
            return []
        try:
            r = requests.get(f"{self.app_center_url}/apps.json", timeout=10)
            return r.json().get("apps", [])
        except Exception:
            return []

    def install_app(self, app_id: str, version: str = None) -> bool:
        apps = self.get_available_apps()
        app_info = next((a for a in apps if a["id"] == app_id), None)
        if not app_info:
            return False
        download_url = app_info.get("download_url")
        checksum = app_info.get("checksum")
        if not download_url:
            return False

        if not requests:
            return False
        r = requests.get(download_url, stream=True, timeout=60)
        r.raise_for_status()
        pkg_path = "/tmp/app.wapp"
        with open(pkg_path, "wb") as f:
            for chunk in r.iter_content(chunk_size=8192):
                f.write(chunk)

        if checksum:
            h = hashlib.sha256()
            with open(pkg_path, "rb") as f:
                h.update(f.read())
            if h.hexdigest() != checksum:
                return False

        install_path = os.path.join(APP_DIR, app_id)
        os.makedirs(install_path, exist_ok=True)
        app_user = self._ensure_app_user(app_id)
        if not app_user:
            shutil.rmtree(install_path, ignore_errors=True)
            return False
        if not self._safe_extract_tar(pkg_path, install_path):
            shutil.rmtree(install_path, ignore_errors=True)
            return False
        try:
            subprocess.run(["chown", "-R", f"{app_user}:{app_user}", install_path], check=True, capture_output=True)
        except subprocess.CalledProcessError:
            shutil.rmtree(install_path, ignore_errors=True)
            return False
        app_data = os.path.join(DATA_APPS_DIR, app_id)
        os.makedirs(app_data, exist_ok=True)
        try:
            subprocess.run(["chown", "-R", f"{app_user}:{app_user}", app_data], check=True, capture_output=True)
        except subprocess.CalledProcessError:
            pass

        manifest_path = os.path.join(install_path, "manifest.json")
        if not os.path.exists(manifest_path):
            shutil.rmtree(install_path, ignore_errors=True)
            return False
        with open(manifest_path) as f:
            manifest = json.load(f)
        port = manifest.get("port", 5000)

        self.conn.execute(
            """
            INSERT OR REPLACE INTO installed_apps
            (app_id, name, version, install_path, status, permissions, port)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
            (
                app_id,
                app_info.get("name", app_id),
                app_info.get("version", "1.0.0"),
                install_path,
                "installed",
                json.dumps(app_info.get("permissions", {})),
                port,
            ),
        )
        self.conn.commit()

        self._install_systemd_unit(app_id, install_path, port)
        self.start_app(app_id)
        return True

    def uninstall_app(self, app_id: str) -> bool:
        self.stop_app(app_id)
        row = self.conn.execute(
            "SELECT install_path FROM installed_apps WHERE app_id = ?", (app_id,)
        ).fetchone()
        self.conn.execute("DELETE FROM installed_apps WHERE app_id = ?", (app_id,))
        self.conn.commit()
        if row:
            path = row[0]
            if os.path.exists(path):
                shutil.rmtree(path, ignore_errors=True)
        unit_name = f"wowos-app-{app_id.replace('.', '-')}.service"
        try:
            subprocess.run(["systemctl", "disable", unit_name], capture_output=True)
            unit_path = os.path.join(SYSTEMD_UNIT_DIR, unit_name)
            if os.path.exists(unit_path):
                os.remove(unit_path)
            subprocess.run(["systemctl", "daemon-reload"], capture_output=True)
        except Exception:
            pass
        safe_id = self._safe_app_id(app_id)
        try:
            subprocess.run(["userdel", f"{WOWAPP_USER_PREFIX}-{safe_id}"], capture_output=True)
        except Exception:
            pass
        return True

    def start_app(self, app_id: str) -> bool:
        unit_name = f"wowos-app-{app_id.replace('.', '-')}.service"
        try:
            subprocess.run(["systemctl", "start", unit_name], check=True, capture_output=True)
            return True
        except subprocess.CalledProcessError:
            return False

    def stop_app(self, app_id: str) -> bool:
        unit_name = f"wowos-app-{app_id.replace('.', '-')}.service"
        try:
            subprocess.run(["systemctl", "stop", unit_name], capture_output=True)
            return True
        except Exception:
            return False

    def list_installed(self) -> List[Dict[str, Any]]:
        rows = self.conn.execute(
            "SELECT app_id, name, version, install_path, status, port FROM installed_apps"
        ).fetchall()
        return [
            {
                "app_id": r[0],
                "name": r[1],
                "version": r[2],
                "install_path": r[3],
                "status": r[4],
                "port": r[5],
            }
            for r in rows
        ]
