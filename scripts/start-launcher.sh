#!/bin/bash
# Start wowOS Launcher (desktop server) for local/dev use. In production use systemd: wowos-launcher.service
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
UI_DIR="${UI_DIR:-$PROJECT_ROOT/ui}"
cd "$UI_DIR"
export WOWOS_API_URL="${WOWOS_API_URL:-http://127.0.0.1:8080}"
export WOWOS_APP_CENTER_URL="${WOWOS_APP_CENTER_URL:-http://127.0.0.1:8000}"
export WOWOS_DESKTOP_PORT="${WOWOS_DESKTOP_PORT:-9090}"
exec python3 desktop_server.py
