"""应用管理服务：安装/更新/卸载、已安装列表、与应用中心通信；安装时生成 systemd unit。"""
import json
import os
import hashlib
import shutil
import sqlite3
import subprocess
import tarfile
from pathlib import Path
from typing import Any, Dict, List, Optional

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

    def _generate_systemd_unit(self, app_id: str, install_path: str, port: int) -> str:
        """生成 systemd unit 内容；实际安装时写入 /etc/systemd/system/。"""
        safe_id = app_id.replace(".", "-").replace("@", "-")
        return f"""[Unit]
Description=wowOS App {app_id}
After=network.target wowos-api.service
Requires=wowos-api.service

[Service]
Type=simple
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

    def _install_systemd_unit(self, app_id: str, install_path: str, port: int) -> bool:
        """生成并安装 systemd unit；需 root。"""
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
        with tarfile.open(pkg_path, "r:gz") as tar:
            tar.extractall(install_path)

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
