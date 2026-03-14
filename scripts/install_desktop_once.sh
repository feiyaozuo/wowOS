#!/usr/bin/env bash
set -euo pipefail

echo "[0/7] ensure admin user and script access"
getent passwd admin >/dev/null || useradd -m -s /bin/bash admin
chmod -R o+rX /opt/wowos/scripts /opt/wowos/ui 2>/dev/null || true

echo "[1/7] wait for time sync (avoid 'Release file is not valid yet')"
systemctl start systemd-timesyncd 2>/dev/null || true
timedatectl set-ntp true 2>/dev/null || true
for _ in 1 2 3 4 5 6; do
  sleep 5
  YEAR=$(date +%Y 2>/dev/null || echo 0)
  if [ "$YEAR" -ge 2024 ]; then break; fi
done
echo "[2/7] apt update (retry if time was wrong)"
for attempt in 1 2 3 4 5; do
  if apt-get update -qq 2>/dev/null; then break; fi
  echo "  attempt $attempt failed, wait 15s and retry..."
  sleep 15
done
apt-get update

echo "[3/7] install desktop packages"
apt-get install -y --no-install-recommends \
  lightdm \
  xserver-xorg \
  xinit \
  openbox \
  xserver-xorg-input-libinput \
  xserver-xorg-video-fbdev \
  libgl1-mesa-dri \
  chromium \
  unclutter \
  fonts-wqy-microhei
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "[4/7] ensure graphical target"
systemctl set-default graphical.target

echo "[5/7] ensure lightdm runtime dirs and enable"
mkdir -p /var/lib/lightdm/data || true
chown -R lightdm:lightdm /var/lib/lightdm || true
systemctl enable lightdm.service || true

echo "[6/7] enable services"
systemctl enable wowos-api.service
systemctl enable wowos-desktop.service
systemctl enable wowos-kiosk.service

echo "[7/7] desktop install finished"
mkdir -p /var/lib/wowos
touch /var/lib/wowos/.desktop_installed
