#!/usr/bin/env python3
"""启动 wowOS 系统服务 API（开发环境：数据目录为 ./data）。"""
import os
import sys

# 确保项目根在 path 中，且开发环境默认数据目录
ROOT = os.path.dirname(os.path.abspath(__file__))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)
os.environ.setdefault("VAR_LIB_WOWOS", os.path.join(ROOT, "data"))
os.environ.setdefault("WOWOS_DATA_PATH", os.path.join(ROOT, "data"))

from wowos_core.api_server import run

if __name__ == "__main__":
    run()
