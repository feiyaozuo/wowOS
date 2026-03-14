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

# 1b. Expand image file so root partition can be resized (avoids "No space left on device" during apt install)
IMG_SIZE_MB=$(($(stat -c%s "$IMG_NAME" 2>/dev/null || stat -f%z "$IMG_NAME") / 1024 / 1024))
NEED_RESIZE=0
if [ "$IMG_SIZE_MB" -lt 19500 ]; then
  NEED_RESIZE=1
  echo "[wowOS] Expanding image to 20GB for desktop + dependencies (current ${IMG_SIZE_MB}MB)"
  truncate -s 20G "$IMG_NAME"
fi

# 2. Attach image to loop device and mount partitions (works with or without partition suffixes)
LOOP_DEV=$(losetup -f --show -P "$IMG_NAME" 2>/dev/null) || LOOP_DEV=$(losetup -f --show "$IMG_NAME")
echo "[wowOS] Loop device: $LOOP_DEV"
if [ -z "$LOOP_DEV" ] || [ ! -b "$LOOP_DEV" ]; then
  echo "[wowOS] Failed to attach loop device for $IMG_NAME (not a valid disk image?)."
  exit 1
fi

# 2a. Resize partition 2 to use full image and grow root filesystem (if we expanded the image)
if [ "$NEED_RESIZE" = "1" ]; then
  echo "[wowOS] Partition table before resize:"
  parted -s "$LOOP_DEV" print 2>/dev/null || sgdisk -p "$LOOP_DEV" 2>/dev/null || true
  echo "[wowOS] blockdev info: $(blockdev --getsize64 "$LOOP_DEV" 2>/dev/null || true) bytes"

  echo "[wowOS] Resizing root partition to 100%"
  RESIZE_OK=0

  # Attempt 1-3: parted with exponential backoff
  for attempt in 1 2 3; do
    if parted -s "$LOOP_DEV" resizepart 2 100%; then
      echo "[wowOS] parted resizepart succeeded (attempt $attempt)"
      RESIZE_OK=1
      break
    fi
    echo "[wowOS] parted retry $attempt/3 failed, waiting $((attempt * 2))s..."
    sleep $((attempt * 2))
  done

  # Fallback: sgdisk (more compatible with kpartx-mapped devices)
  if [ "$RESIZE_OK" = "0" ] && command -v sgdisk >/dev/null 2>&1; then
    echo "[wowOS] Falling back to sgdisk to resize partition 2..."
    DISK_SECTORS=$(blockdev --getsz "$LOOP_DEV" 2>/dev/null || echo "")
    if [ -n "$DISK_SECTORS" ]; then
      # Delete partition 2 and recreate it spanning to end of disk
      START_SECTOR=$(sgdisk -i 2 "$LOOP_DEV" 2>/dev/null | awk '/First sector:/{print $3}')
      if [ -n "$START_SECTOR" ]; then
        if sgdisk -d 2 "$LOOP_DEV" && sgdisk -n "2:${START_SECTOR}:0" "$LOOP_DEV"; then
          echo "[wowOS] sgdisk resize succeeded"
          RESIZE_OK=1
        fi
      fi
    fi
  fi

  if [ "$RESIZE_OK" = "0" ]; then
    echo "[wowOS] ERROR: All partition resize attempts failed. Cannot continue."
    echo "[wowOS] Troubleshooting: ensure parted >= 3.x and gdisk/sgdisk are installed."
    exit 1
  fi

  partprobe "$LOOP_DEV" 2>/dev/null || true
  blockdev --rereadpt "$LOOP_DEV" 2>/dev/null || true
  sleep 3

  echo "[wowOS] Partition table after resize:"
  parted -s "$LOOP_DEV" print 2>/dev/null || sgdisk -p "$LOOP_DEV" 2>/dev/null || true

  # Verify partition 2 was actually resized (should be > half target size)
  # Target is 20GB; expect at least 10GB after resize
  MIN_EXPECTED_PART2_SIZE_MB=10000
  PART2_SIZE_MB=$(parted -s "$LOOP_DEV" unit MB print 2>/dev/null | awk '/^ *2 /{gsub(/MB/,"",$4); print int($4)}' || echo "0")
  echo "[wowOS] Partition 2 size after resize: ${PART2_SIZE_MB}MB"
  if [ "${PART2_SIZE_MB:-0}" -lt "$MIN_EXPECTED_PART2_SIZE_MB" ]; then
    echo "[wowOS] WARNING: Partition 2 may not have been resized correctly (reported ${PART2_SIZE_MB}MB, expected >= ${MIN_EXPECTED_PART2_SIZE_MB}MB). Proceeding anyway."
  fi
fi

mkdir -p /mnt/wowos
if [ -b "${LOOP_DEV}p2" ]; then
  if [ "$NEED_RESIZE" = "1" ]; then
    echo "[wowOS] Growing root filesystem (loop p2)"
    resize2fs "${LOOP_DEV}p2"
  fi
  mount "${LOOP_DEV}p2" /mnt/wowos
  mount "${LOOP_DEV}p1" /mnt/wowos/boot
else
  # Fallback: use kpartx mapper devices (e.g. /dev/mapper/loop0p1)
  echo "[WARNING] losetup -P not available, using kpartx as fallback"
  kpartx -av "$LOOP_DEV"
  MAPPER=$(basename "$LOOP_DEV")
  sleep 2
  if [ "$NEED_RESIZE" = "1" ]; then
    echo "[wowOS] Growing root filesystem (/dev/mapper/${MAPPER}p2)"
    # Attempt resize2fs; it may fail on some kpartx setups but is safe to try since
    # the partition table has already been updated by parted/sgdisk above.
    if resize2fs "/dev/mapper/${MAPPER}p2"; then
      echo "[wowOS] resize2fs succeeded"
    else
      echo "[wowOS] resize2fs failed (exit code $?), continuing"
    fi
  fi
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
echo "[wowOS] Root fs free space before apt:"
df -h /mnt/wowos
FREE_KB=$(df /mnt/wowos | awk 'NR==2 {print $4}')
echo "[wowOS] Free space available: ${FREE_KB}KB ($((FREE_KB/1024))MB)"
REQUIRED_KB=$((5 * 1024 * 1024))
if [ "$FREE_KB" -lt "$REQUIRED_KB" ]; then
  echo "[wowOS] ERROR: Not enough free space! Need at least 5GB, have $((FREE_KB/1024))MB"
  echo "[wowOS] Check partition resize completed: $(parted -s "$LOOP_DEV" print 2>/dev/null || true)"
  exit 1
fi
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
