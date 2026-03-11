#!/usr/bin/env python3
"""启动 mock_os 模拟服务（开发用）。"""
import os
import sys
ROOT = os.path.dirname(os.path.abspath(__file__))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)
os.environ.setdefault("WOWOS_MOCK_AUTO_APPROVE", "1")
from mock_os.server import run
if __name__ == "__main__":
    run()
