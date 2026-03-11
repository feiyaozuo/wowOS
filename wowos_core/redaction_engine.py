"""Data tiering and redaction engine: downgrade/redact by rules. V1 text only."""
import os
import re
from pathlib import Path
from typing import Any, Dict, List

try:
    import yaml
except ImportError:
    yaml = None

_default_rules = str(
    Path(__file__).resolve().parent.parent / "config" / "redaction_rules.yaml"
)
RULES_PATH = os.environ.get("WOWOS_REDACTION_RULES", _default_rules)


class RedactionEngine:
    def __init__(self, rules_path: str = None):
        self.rules_path = rules_path or RULES_PATH
        self.rules = self.load_rules()

    def load_rules(self) -> dict:
        if yaml is None:
            return {}
        path = Path(self.rules_path)
        if not path.exists():
            return {}
        with open(path, "r", encoding="utf-8") as f:
            return yaml.safe_load(f) or {}

    def redact(
        self, data: bytes, data_type: str, source_level: int, target_level: int
    ) -> bytes:
        if source_level <= target_level:
            return data
        rule_key = f"level_{source_level}_to_{target_level}"
        for rule in self.rules.get(rule_key, []):
            if rule.get("type") == data_type:
                data = self.apply_rule(data, rule)
        return data

    def apply_rule(self, data: bytes, rule: Dict[str, Any]) -> bytes:
        if rule.get("type") == "text":
            pattern = rule.get("pattern")
            replace = rule.get("replace", "")
            if pattern:
                try:
                    return re.sub(pattern.encode("utf-8"), replace.encode("utf-8"), data)
                except (re.error, UnicodeDecodeError):
                    try:
                        return re.sub(pattern, replace, data.decode("utf-8")).encode("utf-8")
                    except Exception:
                        return data
        # image/numeric etc. not implemented in V1; return as-is
        return data
