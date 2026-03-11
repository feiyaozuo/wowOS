"""从 .wapp 包内 manifest.json 生成 apps.json 索引。"""
import json
import hashlib
import os
import tarfile
import tempfile
from pathlib import Path

PACKAGES_DIR = os.environ.get("WOWOS_PACKAGES_DIR", "packages")
INDEX_FILE = os.environ.get("WOWOS_INDEX_FILE", "apps.json")
BASE_URL = os.environ.get("WOWOS_APP_CENTER_BASE_URL", "http://localhost:8000")


def read_manifest_from_wapp(wapp_path: str) -> dict:
    with tarfile.open(wapp_path, "r:gz") as tar:
        for m in tar.getmembers():
            if m.name.endswith("manifest.json"):
                f = tar.extractfile(m)
                return json.load(f)
    return {}


def main():
    root = Path(__file__).resolve().parent
    packages_dir = root / PACKAGES_DIR
    if not packages_dir.exists():
        packages_dir.mkdir(parents=True)
    apps = []
    for pkg in sorted(packages_dir.glob("*.wapp")):
        manifest = read_manifest_from_wapp(str(pkg))
        if not manifest:
            continue
        app_id = manifest.get("id") or pkg.stem
        version = manifest.get("version", "1.0.0")
        with open(pkg, "rb") as f:
            checksum = hashlib.sha256(f.read()).hexdigest()
        apps.append({
            "id": app_id,
            "name": manifest.get("name", app_id),
            "version": version,
            "description": manifest.get("description", ""),
            "author": manifest.get("author", ""),
            "license": manifest.get("license", "MIT"),
            "download_url": f"{BASE_URL.rstrip('/')}/packages/{pkg.name}",
            "size": pkg.stat().st_size,
            "checksum": checksum,
            "required_os_version": manifest.get("required_os_version", ">=1.0"),
            "permissions": manifest.get("permissions", {
                "resources": ["file/*"],
                "max_allowed_level": 2,
            }),
        })
    index_path = root / INDEX_FILE
    with open(index_path, "w", encoding="utf-8") as f:
        json.dump({"apps": apps}, f, indent=2, ensure_ascii=False)
    print(f"Generated {index_path} with {len(apps)} app(s).")


if __name__ == "__main__":
    main()
