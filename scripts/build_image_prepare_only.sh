#!/bin/bash
# Prepare-only image: mount, copy wowOS code, create user, configure systemd; no chroot apt-get.
# Use when offline or when chroot cannot pull packages (e.g. in Docker). After flash, on Pi run once:
#   sudo apt update && sudo apt install -y python3 python3-pip sqlite3
#   sudo python3 -m pip install --break-system-packages flask pyjwt cryptography pyyaml requests
# then systemctl start wowos-api
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/build}"
IMG_NAME="${IMG_NAME:-raspios-lite.img}"
WOWOS_VERSION="${WOWOS_VERSION:-1.0}"
WOWOS_UID="${WOWOS_UID:-999}"
WOWOS_GID="${WOWOS_GID:-999}"

echo "[wowOS] Prepare-only build (no chroot apt). Output: $BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

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
    echo "[wowOS] Put Raspberry Pi OS Lite arm64 image at $BUILD_DIR/$IMG_NAME"
    exit 1
  fi
fi
if command -v file >/dev/null && file "$IMG_NAME" | grep -qi "XZ compressed"; then
  echo "[wowOS] Decompressing xz to raw image..."
  xz -d -c "$IMG_NAME" > "${IMG_NAME}.tmp" && mv "${IMG_NAME}.tmp" "$IMG_NAME"
fi

LOOP_DEV=$(losetup -f --show -P "$IMG_NAME" 2>/dev/null) || LOOP_DEV=$(losetup -f --show "$IMG_NAME")
echo "[wowOS] Loop: $LOOP_DEV"
mkdir -p /mnt/wowos
if [ -b "${LOOP_DEV}p2" ]; then
  mount "${LOOP_DEV}p2" /mnt/wowos
  mount "${LOOP_DEV}p1" /mnt/wowos/boot
else
  kpartx -av "$LOOP_DEV"
  MAPPER=$(basename "$LOOP_DEV")
  sleep 1
  mount /dev/mapper/${MAPPER}p2 /mnt/wowos
  mount /dev/mapper/${MAPPER}p1 /mnt/wowos/boot
fi

# Add wowos user inside image (write passwd/group directly)
echo "wowos:x:${WOWOS_GID}:" >> /mnt/wowos/etc/group
echo "wowos:x:${WOWOS_UID}:${WOWOS_GID}:wowOS service:/var/lib/wowos:/bin/false" >> /mnt/wowos/etc/passwd
mkdir -p /mnt/wowos/opt/wowos /mnt/wowos/var/lib/wowos /mnt/wowos/data/files /mnt/wowos/data/apps
cp -r "$PROJECT_ROOT/wowos_core" /mnt/wowos/opt/wowos/
cp -r "$PROJECT_ROOT/config" /mnt/wowos/opt/wowos/
cp "$PROJECT_ROOT/requirements.txt" /mnt/wowos/opt/wowos/ 2>/dev/null || true
chown -R ${WOWOS_UID}:${WOWOS_GID} /mnt/wowos/opt/wowos /mnt/wowos/var/lib/wowos /mnt/wowos/data
chmod 751 /mnt/wowos/data
chmod 700 /mnt/wowos/data/files
chmod 751 /mnt/wowos/data/apps
cp "$PROJECT_ROOT/services/wowos-api.service" /mnt/wowos/etc/systemd/system/
touch /mnt/wowos/boot/ssh
cp "$PROJECT_ROOT/scripts/firstboot_wizard.sh" /mnt/wowos/usr/local/bin/wowos-firstboot 2>/dev/null || true
chmod +x /mnt/wowos/usr/local/bin/wowos-firstboot 2>/dev/null || true

# Write first-boot install-deps script
mkdir -p /mnt/wowos/root
cat > /mnt/wowos/root/wowos-firstboot-install.sh << 'INNER'
#!/bin/bash
# Run once as root on Pi after first boot
apt-get update && apt-get install -y python3 python3-pip sqlite3
python3 -m pip install --break-system-packages flask pyjwt cryptography pyyaml requests
systemctl start wowos-api
echo "wowOS API should be running on port 8080."
INNER
chmod +x /mnt/wowos/root/wowos-firstboot-install.sh

umount /mnt/wowos/boot /mnt/wowos
if [ -b "${LOOP_DEV}p2" ]; then
  losetup -d "$LOOP_DEV"
else
  kpartx -dv "$LOOP_DEV"
  losetup -d "$LOOP_DEV"
fi
rmdir /mnt/wowos 2>/dev/null || true

zip -q "wowos-${WOWOS_VERSION}.img.zip" "$IMG_NAME"
echo "[wowOS] Done: wowos-${WOWOS_VERSION}.img.zip (prepare-only)"
echo "[wowOS] After flash, on the Pi run once: sudo /root/wowos-firstboot-install.sh"
echo "[wowOS] Or install deps manually and: systemctl start wowos-api"
echo "[wowOS] For full build (with deps in image), run ./scripts/build_image.sh on Linux with internet."
