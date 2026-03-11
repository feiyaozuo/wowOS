"""Token 授权服务：颁发、验证、撤销访问令牌。"""
import json
import os
import time
from pathlib import Path
from typing import Any, Dict, List, Optional
from uuid import uuid4

import jwt

# 密钥从环境变量读取，不入库；默认仅开发用
SECRET_KEY = os.environ.get("WOWOS_SECRET_KEY", "device-unique-secret-dev-only")


def _var_lib_wowos() -> str:
    if os.environ.get("VAR_LIB_WOWOS"):
        return os.environ.get("VAR_LIB_WOWOS")
    return os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data"
    )


REVOCATION_DB_PATH = os.environ.get(
    "WOWOS_REVOCATION_DB",
    os.path.join(_var_lib_wowos(), "revocation.json"),
)


def _load_revocation_list() -> set:
    path = Path(REVOCATION_DB_PATH)
    if path.exists():
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            return set(data.get("token_ids", []))
        except (json.JSONDecodeError, IOError):
            return set()
    return set()


def _save_revocation_list(ids: set) -> None:
    path = Path(REVOCATION_DB_PATH)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"token_ids": list(ids)}, indent=2), encoding="utf-8")


def _revocation_list() -> set:
    if not hasattr(_revocation_list, "_cache"):
        _revocation_list._cache = _load_revocation_list()
    return _revocation_list._cache


def _persist_revocation() -> None:
    _save_revocation_list(_revocation_list())


class TokenService:
    @staticmethod
    def generate_token(
        app_id: str,
        user_id: str,
        resources: List[str],
        max_level: int,
        ttl_seconds: int,
        operations: Optional[List[str]] = None,
    ) -> str:
        payload = {
            "token_id": "tkn_" + uuid4().hex[:12],
            "app_id": app_id,
            "user_id": user_id,
            "iat": int(time.time()),
            "exp": int(time.time()) + ttl_seconds,
            "permissions": {
                "resources": resources,
                "max_allowed_level": max_level,
                "operations": operations or ["read", "write"],
            },
        }
        return jwt.encode(payload, SECRET_KEY, algorithm="HS256")

    @staticmethod
    def _resource_matches(allowed: str, required: str) -> bool:
        if allowed == required:
            return True
        if allowed.endswith("/*"):
            prefix = allowed[:-1]
            return required.startswith(prefix) or required == prefix.rstrip("/")
        return False

    @staticmethod
    def verify_token(
        token: str, required_resource: str, required_level: int, operation: str = "read"
    ) -> bool:
        try:
            payload = jwt.decode(token, SECRET_KEY, algorithms=["HS256"])
            if payload["exp"] < time.time():
                return False
            perms = payload.get("permissions", {})
            resources = perms.get("resources", [])
            if not any(
                TokenService._resource_matches(r, required_resource) for r in resources
            ):
                return False
            if perms.get("max_allowed_level", 0) < required_level:
                return False
            if operation not in perms.get("operations", []):
                return False
            if payload["token_id"] in _revocation_list():
                return False
            return True
        except jwt.InvalidTokenError:
            return False

    @staticmethod
    def decode_payload(token: str) -> Optional[Dict[str, Any]]:
        """解析 Token 获取 user_id、app_id 等，用于审计；无效则返回 None。"""
        try:
            payload = jwt.decode(token, SECRET_KEY, algorithms=["HS256"])
            return payload
        except jwt.InvalidTokenError:
            return None

    @staticmethod
    def revoke_token(token_id: str) -> None:
        _revocation_list().add(token_id)
        _persist_revocation()
