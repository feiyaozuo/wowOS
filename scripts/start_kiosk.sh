#!/usr/bin/env bash
set -euo pipefail

export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/home/admin/.Xauthority}"

URL="http://127.0.0.1:9090"

# Wait for X display to become available (needed when launched from systemd
# before LightDM has finished initialising the session).
for _i in $(seq 1 60); do
  if xset q >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

# Wait for the desktop web server to be reachable.
for _i in $(seq 1 30); do
  if command -v curl >/dev/null 2>&1; then
    curl -fsS "$URL" >/dev/null 2>&1 && break
  elif command -v wget >/dev/null 2>&1; then
    wget -q --spider "$URL" 2>/dev/null && break
  fi
  sleep 2
done

exec chromium \
  --kiosk \
  --no-first-run \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --disable-features=Translate \
  --disable-gpu-compositing \
  --disable-dev-shm-usage \
  --disable-crash-reporter \
  "$URL"
