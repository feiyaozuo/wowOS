#!/bin/bash
# Run once on first boot to install Raspberry Pi desktop and set graphical boot.
# State file prevents running again on next boot.
set -e
STATE_FILE="/var/lib/wowos/desktop-installed"
if [ -f "$STATE_FILE" ]; then
  exit 0
fi
apt-get update -qq
apt-get install -y -qq raspberrypi-ui-mods chromium unclutter
# Boot into graphical target after this
systemctl set-default graphical.target
# Autostart wowOS launcher in kiosk for any user logging in
mkdir -p /etc/xdg/autostart
cat > /etc/xdg/autostart/wowos-launcher.desktop << 'EOF'
[Desktop Entry]
Type=Application
Name=wowOS Launcher
Exec=chromium --kiosk --noerrdialogs --disable-infobars --no-first-run --check-for-update-interval=31536000 http://localhost:9090/
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Comment=wowOS desktop home
EOF
touch "$STATE_FILE"
echo "wowOS: desktop install done (first boot). Reboot to enter graphical desktop."
