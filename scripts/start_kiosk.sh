#!/usr/bin/env bash
set -euo pipefail

export DISPLAY=:0
export XAUTHORITY=/home/admin/.Xauthority

URL="http://127.0.0.1:9090"

for i in $(seq 1 30); do
  if curl -fsS "$URL" >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

unclutter -idle 0.5 -root >/dev/null 2>&1 &

exec chromium \
  --kiosk \
  --no-first-run \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --disable-features=Translate \
  "$URL"
