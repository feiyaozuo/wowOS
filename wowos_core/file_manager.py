"""File manager: storage, index, metadata; works with crypto engine, persists as ciphertext."""
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
                category TEXT,
                tags TEXT,
                created_at INTEGER,
                updated_at INTEGER,
                size INTEGER,
                checksum TEXT,
                source TEXT
            )
        """
        )
        self.conn.execute("CREATE INDEX IF NOT EXISTS idx_owner ON files(owner)")
        for col, ctype in [("category", "TEXT"), ("updated_at", "INTEGER"), ("source", "TEXT")]:
            try:
                self.conn.execute(f"ALTER TABLE files ADD COLUMN {col} {ctype}")
            except Exception:
                pass
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
        updated_at = created_at
        metadata.update(
            {
                "file_id": file_id,
                "size": len(data),
                "checksum": checksum,
                "created_at": created_at,
                "updated_at": updated_at,
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
            (file_id, name, privacy_level, owner, category, tags, created_at, updated_at, size, checksum, source)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
            (
                file_id,
                metadata.get("name"),
                metadata.get("privacy_level", 3),
                metadata.get("owner"),
                metadata.get("category"),
                json.dumps(metadata.get("tags", []) if isinstance(metadata.get("tags"), list) else []),
                created_at,
                updated_at,
                metadata.get("size", len(data)),
                checksum,
                metadata.get("source"),
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

    def list_files(self) -> list:
        """Return list of file metadata (file_id, name, level, tags, created_at, updated_at, size, etc.)."""
        try:
            rows = self.conn.execute(
                "SELECT file_id, name, privacy_level, owner, tags, created_at, size, checksum FROM files ORDER BY created_at DESC"
            ).fetchall()
            has_extra = False
        except Exception:
            rows = self.conn.execute(
                "SELECT file_id, name, privacy_level, owner, category, tags, created_at, updated_at, size, checksum, source FROM files ORDER BY created_at DESC"
            ).fetchall()
            has_extra = True
        out = []
        for r in rows:
            if has_extra and len(r) >= 11:
                tags_raw, created_at, updated_at, size, checksum, source = r[5], r[6], r[7], r[8], r[9], r[10]
                category = r[4]
            else:
                tags_raw, created_at = r[5], r[6]
                size = r[7] if len(r) > 7 else None
                checksum = r[8] if len(r) > 8 else None
                updated_at, source, category = created_at, None, None
            tags = tags_raw
            if isinstance(tags, str):
                try:
                    tags = json.loads(tags) if tags else []
                except json.JSONDecodeError:
                    tags = []
            out.append({
                "file_id": r[0],
                "name": r[1] or r[0],
                "privacy_level": r[2],
                "level": r[2],
                "owner": r[3],
                "category": category,
                "tags": tags or [],
                "created_at": created_at,
                "updated_at": updated_at or created_at,
                "size": size,
                "checksum": checksum,
                "source": source,
            })
        return out

    def get_metadata(self, file_id: str) -> Optional[dict]:
        """Return metadata for one file without reading content."""
        try:
            row = self.conn.execute(
                "SELECT file_id, name, privacy_level, owner, tags, created_at, size, checksum FROM files WHERE file_id = ?",
                (file_id,),
            ).fetchone()
            has_extra = False
        except Exception:
            row = self.conn.execute(
                "SELECT file_id, name, privacy_level, owner, category, tags, created_at, updated_at, size, checksum, source FROM files WHERE file_id = ?",
                (file_id,),
            ).fetchone()
            has_extra = True
        if not row:
            return None
        if has_extra and len(row) >= 11:
            category, tags_raw, created_at, updated_at, size, checksum, source = row[4], row[5], row[6], row[7], row[8], row[9], row[10]
        else:
            tags_raw, created_at = row[5], row[6]
            size = row[7] if len(row) > 7 else None
            checksum = row[8] if len(row) > 8 else None
            category, updated_at, source = None, created_at, None
        tags = tags_raw
        if isinstance(tags, str):
            try:
                tags = json.loads(tags) if tags else []
            except json.JSONDecodeError:
                tags = []
        return {
            "file_id": row[0],
            "name": row[1] or row[0],
            "privacy_level": row[2],
            "level": row[2],
            "owner": row[3],
            "category": category,
            "tags": tags or [],
            "created_at": created_at,
            "updated_at": updated_at or created_at,
            "size": size,
            "checksum": checksum,
            "source": source,
        }

    def update_metadata(self, file_id: str, level: int = None, tags: list = None, category: str = None) -> bool:
        """Update level (privacy_level), tags, category. Returns True if updated."""
        updates = []
        args = []
        if level is not None:
            updates.append("privacy_level = ?")
            args.append(level)
        if tags is not None:
            updates.append("tags = ?")
            args.append(json.dumps(tags, ensure_ascii=False))
        if category is not None:
            updates.append("category = ?")
            args.append(category)
        if not updates:
            return False
        updates.append("updated_at = ?")
        args.append(int(time.time()))
        args.append(file_id)
        self.conn.execute(
            f"UPDATE files SET {', '.join(updates)} WHERE file_id = ?", args
        )
        self.conn.commit()
        if self.conn.total_changes:
            meta_path = self._get_file_path(file_id) + ".meta.json"
            if os.path.exists(meta_path):
                with open(meta_path, "r", encoding="utf-8") as f:
                    meta = json.load(f)
                meta["privacy_level"] = level if level is not None else meta.get("privacy_level")
                meta["tags"] = tags if tags is not None else meta.get("tags", [])
                meta["category"] = category if category is not None else meta.get("category")
                meta["updated_at"] = args[-2]
                with open(meta_path, "w", encoding="utf-8") as f:
                    json.dump(meta, f, ensure_ascii=False)
            return True
        return False

    def delete_file(self, file_id: str) -> None:
        file_path = self._get_file_path(file_id)
        for p in (file_path, file_path.replace(".data", ".fek"), file_path + ".meta.json"):
            if os.path.exists(p):
                os.remove(p)
        self.conn.execute("DELETE FROM files WHERE file_id = ?", (file_id,))
        self.conn.commit()
