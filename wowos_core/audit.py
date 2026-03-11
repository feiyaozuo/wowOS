"""审计日志：记录数据访问与脱敏事件。"""
import json
import os
import sqlite3
import time
from typing import Any, Dict

def _default_var_lib():
    return os.environ.get("VAR_LIB_WOWOS") or os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data"
    )


DB_PATH = os.environ.get(
    "WOWOS_AUDIT_DB",
    os.path.join(_default_var_lib(), "audit.db"),
)


class AuditLogger:
    def __init__(self, db_path: str = None):
        self.db_path = db_path or DB_PATH
        os.makedirs(os.path.dirname(self.db_path) or ".", exist_ok=True)
        self.conn = sqlite3.connect(self.db_path)
        self._init_db()

    def _init_db(self) -> None:
        self.conn.execute(
            """
            CREATE TABLE IF NOT EXISTS audit_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp INTEGER,
                event_type TEXT,
                user_id TEXT,
                app_id TEXT,
                resource TEXT,
                original_level INTEGER,
                accessed_level INTEGER,
                redacted BOOLEAN,
                token_id TEXT,
                result TEXT,
                details TEXT
            )
        """
        )
        self.conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_audit_timestamp ON audit_log(timestamp)"
        )
        self.conn.execute("CREATE INDEX IF NOT EXISTS idx_audit_event ON audit_log(event_type)")
        self.conn.commit()

    def log(self, entry: Dict[str, Any]) -> None:
        self.conn.execute(
            """
            INSERT INTO audit_log (
                timestamp, event_type, user_id, app_id, resource,
                original_level, accessed_level, redacted, token_id, result, details
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
            (
                entry.get("timestamp", int(time.time())),
                entry.get("event_type"),
                entry.get("user_id"),
                entry.get("app_id"),
                entry.get("resource"),
                entry.get("original_level"),
                entry.get("accessed_level"),
                1 if entry.get("redacted", False) else 0,
                entry.get("token_id"),
                entry.get("result"),
                json.dumps(entry.get("details", {}), ensure_ascii=False),
            ),
        )
        self.conn.commit()

    def close(self) -> None:
        self.conn.close()
