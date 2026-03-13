#!/usr/bin/env bash
set -euo pipefail

echo "[0/6] ensure admin user and script access"
getent passwd admin >/dev/null || useradd -m -s /bin/bash admin
chmod -R o+rX /opt/wowos/scripts /opt/wowos/ui 2>/dev/null || true

echo "[1/6] apt update"
apt-get update

echo "[2/6] install desktop packages"
apt-get install -y \
  lightdm \
  xserver-xorg \
  xinit \
  openbox \
  chromium \
  unclutter

echo "[3/6] ensure graphical target"
systemctl set-default graphical.target

echo "[4/6] ensure lightdm runtime dirs"
mkdir -p /var/lib/lightdm/data || true
chown -R lightdm:lightdm /var/lib/lightdm || true

echo "[5/6] enable services"
systemctl enable wowos-api.service
systemctl enable wowos-desktop.service
systemctl enable wowos-kiosk.service

echo "[6/6] desktop install finished"
mkdir -p /var/lib/wowos
touch /var/lib/wowos/.desktop_installed
