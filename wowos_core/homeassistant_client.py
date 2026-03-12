"""Home Assistant light client: connect, list entities, basic control (lights, switches, scenes)."""
import os
from typing import Any, Dict, List, Optional

try:
    import requests
except ImportError:
    requests = None

try:
    import yaml
except ImportError:
    yaml = None

CONFIG_PATH = os.environ.get(
    "WOWOS_HA_CONFIG",
    os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "config", "homeassistant.yaml"),
)


def _load_config() -> dict:
    if not yaml:
        return {}
    if not os.path.exists(CONFIG_PATH):
        return {}
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def _base_and_token(base_url: str = None, token: str = None) -> tuple:
    cfg = _load_config()
    base_url = (base_url or os.environ.get("WOWOS_HA_URL") or cfg.get("base_url") or "").rstrip("/")
    token = token or os.environ.get("WOWOS_HA_TOKEN") or cfg.get("token") or ""
    return base_url, token


def test_connection(base_url: str = None, token: str = None) -> bool:
    """Test connection to Home Assistant. Returns True if GET /api/ returns 200."""
    if not requests:
        return False
    base_url, token = _base_and_token(base_url, token)
    if not base_url or not token:
        return False
    try:
        r = requests.get(
            f"{base_url}/api/",
            headers={"Authorization": f"Bearer {token}"},
            timeout=10,
        )
        return r.status_code == 200
    except Exception:
        return False


def get_states(base_url: str = None, token: str = None) -> List[Dict[str, Any]]:
    """Fetch all entity states from GET /api/states."""
    if not requests:
        return []
    base_url, token = _base_and_token(base_url, token)
    if not base_url or not token:
        return []
    try:
        r = requests.get(
            f"{base_url}/api/states",
            headers={"Authorization": f"Bearer {token}"},
            timeout=10,
        )
        r.raise_for_status()
        return r.json() or []
    except Exception:
        return []


def call_service(
    base_url: str,
    token: str,
    domain: str,
    service: str,
    entity_id: str = None,
    data: dict = None,
) -> bool:
    """Call a Home Assistant service (e.g. light.turn_on, switch.turn_off)."""
    if not requests:
        return False
    base_url = base_url.rstrip("/")
    if not base_url or not token:
        return False
    payload = data or {}
    if entity_id:
        payload["entity_id"] = entity_id
    try:
        r = requests.post(
            f"{base_url}/api/services/{domain}/{service}",
            headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
            json=payload,
            timeout=10,
        )
        return r.status_code in (200, 201)
    except Exception:
        return False
