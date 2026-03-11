"""文件管理抽象层：存储、索引、元数据；与加密引擎配合，存盘为密文。"""
import json
import os
import hashlib
import time
from pathlib import Path
from typing import Optional, Tuple
from uuid import uuid4

from wowos_core.crypto_engine import CryptoEngine


def _default_data_path() -> str:
    if os.environ.get("WOWOS_DATA_PATH"):
        return os.environ.get("WOWOS_DATA_PATH")
    return os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data"
    )


class FileManager:
    def __init__(self, base_path: str = None):
        self.base_path = base_path or _default_data_path()
        self.files_path = os.path.join(self.base_path, "files")
        self.meta_db = os.path.join(self.base_path, "metadata.db")
        os.makedirs(self.files_path, exist_ok=True)
        self._init_db()

    def _init_db(self) -> None:
        import sqlite3

        self.conn = sqlite3.connect(self.meta_db)
        self.conn.execute(
            """
            CREATE TABLE IF NOT EXISTS files (
                file_id TEXT PRIMARY KEY,
                name TEXT,
                privacy_level INTEGER DEFAULT 3,
                owner TEXT,
                tags TEXT,
                created_at INTEGER,
                size INTEGER,
                checksum TEXT
            )
        """
        )
        self.conn.execute("CREATE INDEX IF NOT EXISTS idx_owner ON files(owner)")
        self.conn.commit()

    def _generate_file_id(self) -> str:
        return "file_" + uuid4().hex[:16]

    def _get_file_path(self, file_id: str) -> str:
        subdir = file_id[:2] if len(file_id) >= 2 else "f0"
        dir_path = os.path.join(self.files_path, subdir)
        os.makedirs(dir_path, exist_ok=True)
        return os.path.join(dir_path, file_id + ".data")

    def store_file(self, data: bytes, metadata: dict) -> str:
        file_id = metadata.get("file_id") or self._generate_file_id()
        checksum = hashlib.sha256(data).hexdigest()
        created_at = metadata.get("created_at") or int(time.time())
        metadata.update(
            {
                "file_id": file_id,
                "size": len(data),
                "checksum": checksum,
                "created_at": created_at,
            }
        )
        encrypted_data, encrypted_fek = CryptoEngine.encrypt_file(data)
        file_path = self._get_file_path(file_id)
        with open(file_path, "wb") as f:
            f.write(encrypted_data)
        fek_path = file_path.replace(".data", ".fek")
        with open(fek_path, "wb") as f:
            f.write(encrypted_fek)
        meta_path = file_path + ".meta.json"
        meta_for_disk = {k: v for k, v in metadata.items() if k != "file_id"}
        meta_for_disk["file_id"] = file_id
        with open(meta_path, "w", encoding="utf-8") as f:
            json.dump(meta_for_disk, f, ensure_ascii=False)
        self.conn.execute(
            """
            INSERT OR REPLACE INTO files
            (file_id, name, privacy_level, owner, tags, created_at, size, checksum)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
            (
                file_id,
                metadata.get("name"),
                metadata.get("privacy_level", 3),
                metadata.get("owner"),
                json.dumps(metadata.get("tags", [])),
                created_at,
                metadata.get("size"),
                checksum,
            ),
        )
        self.conn.commit()
        return file_id

    def read_file(self, file_id: str) -> Tuple[Optional[bytes], Optional[dict]]:
        file_path = self._get_file_path(file_id)
        if not os.path.exists(file_path):
            return None, None
        with open(file_path, "rb") as f:
            encrypted_data = f.read()
        fek_path = file_path.replace(".data", ".fek")
        if not os.path.exists(fek_path):
            return None, None
        with open(fek_path, "rb") as f:
            encrypted_fek = f.read()
        try:
            data = CryptoEngine.decrypt_file(encrypted_data, encrypted_fek)
        except Exception:
            return None, None
        meta_path = file_path + ".meta.json"
        with open(meta_path, "r", encoding="utf-8") as f:
            metadata = json.load(f)
        return data, metadata

    def delete_file(self, file_id: str) -> None:
        file_path = self._get_file_path(file_id)
        for p in (file_path, file_path.replace(".data", ".fek"), file_path + ".meta.json"):
            if os.path.exists(p):
                os.remove(p)
        self.conn.execute("DELETE FROM files WHERE file_id = ?", (file_id,))
        self.conn.commit()
