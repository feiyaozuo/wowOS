#!/usr/bin/env python3
"""Start mock_os (dev/test)."""
import os
import sys
ROOT = os.path.dirname(os.path.abspath(__file__))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)
os.environ.setdefault("WOWOS_MOCK_AUTO_APPROVE", "1")
from mock_os.server import run
if __name__ == "__main__":
    run()
