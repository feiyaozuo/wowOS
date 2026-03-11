#!/usr/bin/env python3
"""Start wowOS system API (dev: data dir is ./data)."""
import os
import sys

# Ensure project root on path and dev default data dir
ROOT = os.path.dirname(os.path.abspath(__file__))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)
os.environ.setdefault("VAR_LIB_WOWOS", os.path.join(ROOT, "data"))
os.environ.setdefault("WOWOS_DATA_PATH", os.path.join(ROOT, "data"))

from wowos_core.api_server import run

if __name__ == "__main__":
    run()
