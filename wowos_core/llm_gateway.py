"""LLM gateway: controlled external call to DeepSeek/Kimi (OpenAI-compatible). Audit and optional redact."""
import os
from pathlib import Path
from typing import Any, Dict, List, Optional

try:
    import yaml
except ImportError:
    yaml = None

CONFIG_PATH = os.environ.get(
    "WOWOS_LLM_PROVIDERS",
    os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "config", "llm_providers.yaml"),
)


def _load_providers() -> dict:
    if not yaml or not os.path.exists(CONFIG_PATH):
        return {}
    with open(CONFIG_PATH, "r", encoding="utf-8") as f:
        data = yaml.safe_load(f) or {}
    return data.get("providers") or {}


def get_provider(provider_id: str) -> Optional[Dict[str, Any]]:
    """Return provider config with api_key resolved from env via api_key_env."""
    providers = _load_providers()
    cfg = providers.get(provider_id)
    if not cfg:
        return None
    cfg = dict(cfg)
    env_name = cfg.get("api_key_env") or ""
    api_key = os.environ.get(env_name, "") if env_name else ""
    cfg["api_key"] = api_key
    return cfg


def list_providers() -> List[Dict[str, Any]]:
    """Return list of provider ids and names (no api_key)."""
    providers = _load_providers()
    return [{"id": k, "name": (v.get("name") or k)} for k, v in providers.items()]


def test_connection(provider_id: str) -> bool:
    """Test provider with a minimal request."""
    cfg = get_provider(provider_id)
    if not cfg or not cfg.get("api_key"):
        return False
    try:
        import requests
        base = (cfg.get("base_url") or "").rstrip("/")
        model = cfg.get("model") or "gpt-3.5-turbo"
        r = requests.post(
            f"{base}/chat/completions",
            headers={
                "Authorization": f"Bearer {cfg['api_key']}",
                "Content-Type": "application/json",
            },
            json={
                "model": model,
                "messages": [{"role": "user", "content": "Hi"}],
                "max_tokens": 5,
            },
            timeout=15,
        )
        return r.status_code == 200
    except Exception:
        return False


def analyze_file(
    file_id: str,
    provider_id: str,
    prompt: str,
    redact_first: bool,
    file_manager,
    redaction_engine,
) -> tuple:
    """
    Read file (optionally redact to L1), send to LLM, return (content, error).
    Caller must write audit log.
    """
    cfg = get_provider(provider_id)
    if not cfg or not cfg.get("api_key"):
        return None, "Provider not configured or missing api_key"
    data, metadata = file_manager.read_file(file_id)
    if data is None:
        return None, "File not found"
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        text = "(binary content omitted)"
    original_level = metadata.get("privacy_level", 3)
    if redact_first and original_level > 1:
        data_type = metadata.get("type") or "text"
        redacted = redaction_engine.redact(data, data_type, original_level, 1)
        try:
            text = redacted.decode("utf-8")
        except UnicodeDecodeError:
            text = "(redacted binary)"
    user_content = (prompt or "Summarize the following.") + "\n\n---\n\n" + text[:32000]
    try:
        import requests
        base = (cfg.get("base_url") or "").rstrip("/")
        model = cfg.get("model") or "gpt-3.5-turbo"
        r = requests.post(
            f"{base}/chat/completions",
            headers={
                "Authorization": f"Bearer {cfg['api_key']}",
                "Content-Type": "application/json",
            },
            json={
                "model": model,
                "messages": [{"role": "user", "content": user_content}],
                "max_tokens": 2048,
            },
            timeout=60,
        )
        r.raise_for_status()
        out = r.json()
        choices = out.get("choices") or []
        if not choices:
            return None, "No response"
        msg = choices[0].get("message") or {}
        return (msg.get("content") or "").strip(), None
    except Exception as e:
        return None, str(e)
