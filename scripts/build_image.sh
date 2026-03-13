#!/bin/bash
# Build wowOS image from Raspberry Pi OS Lite (requires root or sudo)
# Run on Linux or use Docker/VM that provides losetup, mount, chroot
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${BUILD_DIR:-/tmp/wowos-build}"
IMG_NAME="${IMG_NAME:-raspios-lite.img}"
WOWOS_VERSION="${WOWOS_VERSION:-1.0}"

echo "[wowOS] Build dir: $BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# 1. Download base image if missing
if [ ! -f "$IMG_NAME" ]; then
  echo "[wowOS] Downloading base image..."
  wget -L -q --show-progress "https://downloads.raspberrypi.org/raspios_lite_arm64_latest" -O raspios-dl || true
  if [ -f raspios-dl ]; then
    if command -v file >/dev/null && file raspios-dl | grep -qi "XZ compressed"; then
      xz -d -c raspios-dl > "$IMG_NAME" && rm -f raspios-dl
    elif command -v file >/dev/null && file raspios-dl | grep -qi "gzip"; then
      gzip -d -c raspios-dl > "$IMG_NAME" && rm -f raspios-dl
    else
      mv raspios-dl "$IMG_NAME"
    fi
  fi
  if [ ! -f "$IMG_NAME" ]; then
    echo "[wowOS] Manual: place Raspberry Pi OS Lite image at $BUILD_DIR/$IMG_NAME"
    exit 1
  fi
fi
if command -v file >/dev/null && file "$IMG_NAME" | grep -qi "XZ compressed"; then
  echo "[wowOS] Decompressing xz to raw image..."
  xz -d -c "$IMG_NAME" > "${IMG_NAME}.tmp" && mv "${IMG_NAME}.tmp" "$IMG_NAME"
fi

# 2. Mount image (requires root)
LOOP_DEV=$(losetup -f --show -P "$IMG_NAME")
echo "[wowOS] Loop device: $LOOP_DEV"
mkdir -p /mnt/wowos
mount "${LOOP_DEV}p2" /mnt/wowos
mount "${LOOP_DEV}p1" /mnt/wowos/boot

# 3. chroot install deps
mount --bind /dev /mnt/wowos/dev
mount --bind /proc /mnt/wowos/proc
mount --bind /sys /mnt/wowos/sys
chroot /mnt/wowos apt-get update
chroot /mnt/wowos apt-get install -y python3 python3-pip sqlite3
chroot /mnt/wowos python3 -m pip install --break-system-packages flask pyjwt cryptography pyyaml requests

# 4. Create wowos user/group (API runs as this user)
chroot /mnt/wowos groupadd -r wowos 2>/dev/null || true
chroot /mnt/wowos useradd -r -s /bin/false -g wowos -d /var/lib/wowos wowos 2>/dev/null || true

# 5. Copy wowOS core and desktop UI
mkdir -p /mnt/wowos/opt/wowos
cp -r "$PROJECT_ROOT/wowos_core" /mnt/wowos/opt/wowos/
cp -r "$PROJECT_ROOT/config" /mnt/wowos/opt/wowos/
cp -r "$PROJECT_ROOT/ui" /mnt/wowos/opt/wowos/ 2>/dev/null || true
cp "$PROJECT_ROOT/requirements.txt" /mnt/wowos/opt/wowos/ 2>/dev/null || true
chroot /mnt/wowos chown -R wowos:wowos /opt/wowos

# 6. systemd services
cp "$PROJECT_ROOT/services/wowos-api.service" /mnt/wowos/etc/systemd/system/
cp "$PROJECT_ROOT/services/wowos-desktop.service" /mnt/wowos/etc/systemd/system/ 2>/dev/null || true
chroot /mnt/wowos systemctl enable wowos-api.service
chroot /mnt/wowos systemctl enable wowos-desktop.service 2>/dev/null || true

# 7. Data and config dirs (owned by wowos; /data/files wowos-only, data access via API only)
chroot /mnt/wowos mkdir -p /var/lib/wowos /data/files /data/apps
chroot /mnt/wowos chown -R wowos:wowos /var/lib/wowos /data
chroot /mnt/wowos chmod 751 /data
chroot /mnt/wowos chmod 700 /data/files
chroot /mnt/wowos chmod 751 /data/apps

# 8. Enable SSH (headless after flash; Raspberry Pi OS enables SSH when boot partition has 'ssh' file)
touch /mnt/wowos/boot/ssh

# 9. First-boot script (run wowos-firstboot after login to set device password)
cp "$PROJECT_ROOT/scripts/firstboot_wizard.sh" /mnt/wowos/usr/local/bin/wowos-firstboot 2>/dev/null || true
chroot /mnt/wowos chmod +x /usr/local/bin/wowos-firstboot 2>/dev/null || true

# 9b. 方案2：桌面与 kiosk — 脚本放到 /opt/wowos/scripts/
mkdir -p /mnt/wowos/opt/wowos/scripts
cp "$PROJECT_ROOT/scripts/install_desktop_once.sh" /mnt/wowos/opt/wowos/scripts/
cp "$PROJECT_ROOT/scripts/start_kiosk.sh" /mnt/wowos/opt/wowos/scripts/
chroot /mnt/wowos chmod +x /opt/wowos/scripts/install_desktop_once.sh /opt/wowos/scripts/start_kiosk.sh
cp "$PROJECT_ROOT/services/wowos-install-desktop-once.service" /mnt/wowos/etc/systemd/system/
cp "$PROJECT_ROOT/services/wowos-kiosk.service" /mnt/wowos/etc/systemd/system/
chroot /mnt/wowos systemctl enable wowos-install-desktop-once.service
chroot /mnt/wowos systemctl enable wowos-kiosk.service

# 10. Unmount
umount /mnt/wowos/dev /mnt/wowos/proc /mnt/wowos/sys
umount /mnt/wowos/boot /mnt/wowos
losetup -d "$LOOP_DEV"
rmdir /mnt/wowos 2>/dev/null || true

# 11. Zip
zip -q "wowos-${WOWOS_VERSION}.img.zip" "$IMG_NAME"
echo "[wowOS] Done: wowos-${WOWOS_VERSION}.img.zip"
echo "[wowOS] Flash to SD, boot Pi; SSH enabled, API on port 8080. Optional: run wowos-firstboot to set device password."
