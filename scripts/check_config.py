"""Minimal self-check for YAML config parsing.

Run from repo root:
    python3 scripts/check_config.py
"""
from pathlib import Path

import yaml


def main() -> None:
    for rel in ("config/data_levels.yaml", "config/llm_providers.yaml"):
        p = Path(__file__).resolve().parent.parent / rel
        data = yaml.safe_load(p.read_text(encoding="utf-8"))
        if not data:
            raise SystemExit(f"{rel} parsed empty")
        print(f"{rel} OK -> keys: {list(data.keys())}")


if __name__ == "__main__":
    main()

