#!/usr/bin/env bash
set -euo pipefail

export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/home/admin/.Xauthority}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

URL="http://127.0.0.1:9090"
LOG_FILE="/home/admin/wowos-kiosk.log"

echo "[kiosk] boot at $(date '+%F %T')" >> "$LOG_FILE"

for _i in $(seq 1 60); do
  if xset q >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

for _i in $(seq 1 60); do
  if command -v curl >/dev/null 2>&1; then
    curl -fsS "$URL" >/dev/null 2>&1 && break
  elif command -v wget >/dev/null 2>&1; then
    wget -q --spider "$URL" 2>/dev/null && break
  fi
  sleep 2
done

while true; do
  chromium \
    --kiosk \
    --ozone-platform=x11 \
    --no-first-run \
    --disable-infobars \
    --disable-session-crashed-bubble \
    --disable-features=Translate \
    --disable-gpu-compositing \
    --disable-dev-shm-usage \
    --disable-crash-reporter \
    "$URL" >> "$LOG_FILE" 2>&1 || true

  echo "[kiosk] chromium exited, restarting at $(date '+%F %T')" >> "$LOG_FILE"
  sleep 2
done
