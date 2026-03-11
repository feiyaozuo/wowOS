"""wowOS SDK：应用通过本 SDK 调用 OS API。支持 mock 模式连接 mock_os。"""
import json
import os
from typing import Any, Dict, List, Optional

try:
    import requests
except ImportError:
    requests = None


class Client:
    def __init__(
        self,
        app_id: str,
        api_base: str = None,
        mock: bool = None,
    ):
        self.app_id = app_id
        if mock is None:
            mock = os.environ.get("WOWOS_MOCK", "0") == "1"
        if mock:
            self.api_base = os.environ.get(
                "WOWOS_MOCK_API", "http://localhost:8081/api/v1"
            )
            self.token = os.environ.get("WOWOS_MOCK_TOKEN", "mock-token-for-testing")
        else:
            self.api_base = api_base or os.environ.get(
                "WOWOS_API_URL", "http://localhost:8080/api/v1"
            )
            self.token = self._load_token()

    def _load_token(self) -> Optional[str]:
        token_path = os.path.join(
            os.environ.get("WOWOS_APP_DIR", "/apps"), self.app_id, "token.json"
        )
        if os.path.exists(token_path):
            with open(token_path) as f:
                return json.load(f).get("token")
        return None

    def request_access(
        self,
        resources: List[str],
        max_level: int,
        ttl: int = 3600,
    ) -> Optional[str]:
        if not requests:
            return None
        resp = requests.post(
            f"{self.api_base}/tokens",
            json={
                "app_id": self.app_id,
                "resources": resources,
                "max_level": max_level,
                "ttl": ttl,
            },
            headers={"Authorization": f"Bearer {self.token}"},
            timeout=10,
        )
        if resp.status_code == 200:
            return resp.json().get("token")
        return None

    def read_file(self, file_id: str, level: int = 3) -> Optional[bytes]:
        if not requests:
            return None
        resp = requests.get(
            f"{self.api_base}/files/{file_id}",
            params={"level": level},
            headers={"Authorization": f"Bearer {self.token}"},
            timeout=30,
        )
        if resp.status_code == 200:
            return resp.content
        return None

    def upload_file(
        self,
        data: bytes,
        name: str,
        privacy_level: int = 3,
        tags: List[str] = None,
    ) -> Optional[str]:
        if not requests:
            return None
        files = {"file": (name, data)}
        data_form = {
            "privacy_level": privacy_level,
            "tags": json.dumps(tags or []),
        }
        resp = requests.post(
            f"{self.api_base}/files",
            files=files,
            data=data_form,
            headers={"Authorization": f"Bearer {self.token}"},
            timeout=30,
        )
        if resp.status_code == 200:
            return resp.json().get("file_id")
        return None

    def call_app(
        self,
        app_id: str,
        path: str,
        method: str = "GET",
        data: dict = None,
    ) -> Optional[Dict[str, Any]]:
        base = os.environ.get("WOWOS_GATEWAY", "http://localhost")
        url = f"{base.rstrip('/')}/apps/{app_id}{path}"
        if not requests:
            return None
        headers = {"Authorization": f"Bearer {self.token}"}
        if method == "GET":
            resp = requests.get(url, headers=headers, timeout=10)
        else:
            resp = requests.post(url, json=data or {}, headers=headers, timeout=10)
        try:
            return resp.json()
        except Exception:
            return None
