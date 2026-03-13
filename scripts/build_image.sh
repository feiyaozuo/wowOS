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

# 2. Attach image to loop device and mount partitions (works with or without partition suffixes)
LOOP_DEV=$(losetup -f --show -P "$IMG_NAME" 2>/dev/null) || LOOP_DEV=$(losetup -f --show "$IMG_NAME")
echo "[wowOS] Loop device: $LOOP_DEV"
if [ -z "$LOOP_DEV" ] || [ ! -b "$LOOP_DEV" ]; then
  echo "[wowOS] Failed to attach loop device for $IMG_NAME (not a valid disk image?)."
  exit 1
fi
mkdir -p /mnt/wowos
if [ -b "${LOOP_DEV}p2" ]; then
  mount "${LOOP_DEV}p2" /mnt/wowos
  mount "${LOOP_DEV}p1" /mnt/wowos/boot
else
  # Fallback: use kpartx mapper devices (e.g. /dev/mapper/loop0p1)
  kpartx -av "$LOOP_DEV"
  MAPPER=$(basename "$LOOP_DEV")
  sleep 1
  mount /dev/mapper/${MAPPER}p2 /mnt/wowos
  mount /dev/mapper/${MAPPER}p1 /mnt/wowos/boot
fi

# 2b. When building on x86_64 (e.g. CI), copy qemu into chroot so arm64 binaries run via emulation
if [ -f /usr/bin/qemu-aarch64-static ]; then
  echo "[wowOS] Copying qemu-aarch64-static into chroot for arm64 emulation"
  mkdir -p /mnt/wowos/usr/bin
  cp -f /usr/bin/qemu-aarch64-static /mnt/wowos/usr/bin/
  chmod 755 /mnt/wowos/usr/bin/qemu-aarch64-static
fi

# 3. chroot install base deps (Python + desktop + kiosk) so the image is self-contained
mount --bind /dev /mnt/wowos/dev
mount --bind /proc /mnt/wowos/proc
mount --bind /sys /mnt/wowos/sys
# Use host-side apt cache dir so the image rootfs is not filled (CI has limited space in image)
APT_CACHE="${BUILD_DIR}/.apt-cache"
mkdir -p /mnt/wowos/var/cache/apt/archives "$APT_CACHE"
mount --bind "$APT_CACHE" /mnt/wowos/var/cache/apt/archives
chroot /mnt/wowos apt-get update
chroot /mnt/wowos apt-get install -y \
  python3 python3-pip python3-venv sqlite3 \
  lightdm xserver-xorg xinit openbox \
  chromium unclutter \
  dbus-x11 x11-xserver-utils \
  network-manager \
  fonts-noto fonts-noto-cjk

# 4. Create wowos service user/group (API runs as this user) and desktop user
chroot /mnt/wowos groupadd -r wowos 2>/dev/null || true
chroot /mnt/wowos useradd -r -s /bin/false -g wowos -d /var/lib/wowos wowos 2>/dev/null || true
chroot /mnt/wowos id admin >/dev/null 2>&1 || chroot /mnt/wowos useradd -m -s /bin/bash admin

# 5. Copy wowOS core and desktop UI
mkdir -p /mnt/wowos/opt/wowos
cp -r "$PROJECT_ROOT/wowos_core" /mnt/wowos/opt/wowos/
cp -r "$PROJECT_ROOT/config" /mnt/wowos/opt/wowos/
cp -r "$PROJECT_ROOT/ui" /mnt/wowos/opt/wowos/ 2>/dev/null || true
cp "$PROJECT_ROOT/requirements.txt" /mnt/wowos/opt/wowos/ 2>/dev/null || true
chroot /mnt/wowos chown -R wowos:wowos /opt/wowos

# 5b. Install Python dependencies from requirements.txt inside the image
if [ -f "$PROJECT_ROOT/requirements.txt" ]; then
  chroot /mnt/wowos python3 -m pip install --break-system-packages -r /opt/wowos/requirements.txt
fi

# 6. systemd services
cp "$PROJECT_ROOT/services/wowos-api.service" /mnt/wowos/etc/systemd/system/
cp "$PROJECT_ROOT/services/wowos-desktop.service" /mnt/wowos/etc/systemd/system/ 2>/dev/null || true
cp "$PROJECT_ROOT/services/wowos-kiosk.service" /mnt/wowos/etc/systemd/system/

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

# 9b. Desktop & kiosk: copy scripts and configure LightDM autologin + Openbox autostart
mkdir -p /mnt/wowos/opt/wowos/scripts
cp "$PROJECT_ROOT/scripts/start_kiosk.sh" /mnt/wowos/opt/wowos/scripts/
chroot /mnt/wowos chmod +x /opt/wowos/scripts/start_kiosk.sh

# LightDM autologin for admin, using Openbox session
chroot /mnt/wowos mkdir -p /etc/lightdm/lightdm.conf.d
cat > /mnt/wowos/etc/lightdm/lightdm.conf.d/50-wowos-autologin.conf << 'EOF'
[Seat:*]
autologin-user=admin
autologin-user-timeout=0
user-session=openbox
EOF

# Openbox autostart to launch kiosk after X session is ready
mkdir -p /mnt/wowos/home/admin/.config/openbox
cat > /mnt/wowos/home/admin/.config/openbox/autostart << 'EOF'
xset -dpms
xset s off
xset s noblank
unclutter -idle 0.5 -root >/dev/null 2>&1 &
/opt/wowos/scripts/start_kiosk.sh &
EOF
chroot /mnt/wowos chown -R admin:admin /home/admin/.config

# Enable services and graphical target inside the image
chroot /mnt/wowos systemctl enable lightdm
chroot /mnt/wowos systemctl enable wowos-api.service
chroot /mnt/wowos systemctl enable wowos-desktop.service 2>/dev/null || true
chroot /mnt/wowos systemctl enable wowos-kiosk.service
chroot /mnt/wowos systemctl set-default graphical.target

# 10. Unmount and detach loop device (handle both direct loop partitions and kpartx mappers)
umount /mnt/wowos/var/cache/apt/archives 2>/dev/null || true
rm -rf "${BUILD_DIR}/.apt-cache" 2>/dev/null || true
umount /mnt/wowos/dev /mnt/wowos/proc /mnt/wowos/sys 2>/dev/null || true
umount /mnt/wowos/boot /mnt/wowos
if [ -b "${LOOP_DEV}p2" ]; then
  losetup -d "$LOOP_DEV"
else
  kpartx -dv "$LOOP_DEV"
  losetup -d "$LOOP_DEV"
fi
rmdir /mnt/wowos 2>/dev/null || true

# 11. Zip
zip -q "wowos-${WOWOS_VERSION}.img.zip" "$IMG_NAME"
echo "[wowOS] Done: wowos-${WOWOS_VERSION}.img.zip"
echo "[wowOS] Flash to SD, boot Pi; SSH enabled, API on port 8080. Optional: run wowos-firstboot to set device password."
