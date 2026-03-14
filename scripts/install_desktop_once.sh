#!/usr/bin/env bash
set -euo pipefail

echo "[0/9] ensure admin user and script access"
getent passwd admin >/dev/null || useradd -m -s /bin/bash admin
usermod -aG video,input admin 2>/dev/null || true
chmod -R o+rX /opt/wowos/scripts /opt/wowos/ui 2>/dev/null || true

echo "[1/9] wait for time sync (avoid 'Release file is not valid yet')"
systemctl start systemd-timesyncd 2>/dev/null || true
timedatectl set-ntp true 2>/dev/null || true
for _ in 1 2 3 4 5 6; do
  sleep 5
  YEAR=$(date +%Y 2>/dev/null || echo 0)
  if [ "$YEAR" -ge 2024 ]; then break; fi
done
echo "[2/9] apt update (retry if time was wrong)"
for attempt in 1 2 3 4 5; do
  if apt-get update -qq 2>/dev/null; then break; fi
  echo "  attempt $attempt failed, wait 15s and retry..."
  sleep 15
done
apt-get update

echo "[3/9] install desktop packages"
apt-get install -y --no-install-recommends \
  lightdm \
  lightdm-gtk-greeter \
  xserver-xorg \
  xinit \
  openbox \
  xserver-xorg-input-libinput \
  xserver-xorg-video-fbdev \
  libgl1-mesa-dri \
  chromium \
  unclutter \
  curl \
  dbus-x11 \
  x11-xserver-utils \
  network-manager \
  fonts-wqy-microhei
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "[4/9] ensure graphical target"
systemctl set-default graphical.target

echo "[5/9] ensure lightdm runtime dirs and enable"
mkdir -p /var/lib/lightdm/data || true
chown -R lightdm:lightdm /var/lib/lightdm || true
systemctl enable lightdm.service || true

echo "[6/9] configure LightDM autologin for admin with Openbox session"
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/50-wowos-autologin.conf << 'AUTOLOGIN'
[Seat:*]
autologin-user=admin
autologin-user-timeout=0
user-session=openbox
greeter-session=lightdm-gtk-greeter
AUTOLOGIN

echo "[7/9] configure Openbox autostart (display settings)"
mkdir -p /home/admin/.config/openbox
cat > /home/admin/.config/openbox/autostart << 'AUTOSTART'
xset -dpms
xset s off
xset s noblank
unclutter -idle 0.5 -root >/dev/null 2>&1 &
AUTOSTART
chown -R admin:admin /home/admin/.config

echo "[8/9] enable services"
systemctl enable wowos-api.service
systemctl enable wowos-desktop.service
systemctl enable wowos-kiosk.service

echo "[9/9] desktop install finished — rebooting into graphical desktop"
mkdir -p /var/lib/wowos
touch /var/lib/wowos/.desktop_installed
systemctl reboot
