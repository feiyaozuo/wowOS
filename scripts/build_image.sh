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

grow_root_fs() {
  local DEV="$1"
  echo "[wowOS] Growing root filesystem ($DEV)"
  echo "[wowOS] resize2fs version: $(resize2fs -V 2>&1 | head -1)"
  echo "[wowOS] e2fsck running first to ensure fs consistency..."
  e2fsck -f -y "$DEV" || true
  RESIZE_RC=0
  resize2fs "$DEV" || RESIZE_RC=$?
  if [ "$RESIZE_RC" -eq 0 ]; then
    echo "[wowOS] resize2fs succeeded"
  else
    echo "[wowOS] resize2fs failed (exit code $RESIZE_RC)"
    echo "[wowOS] Filesystem features: $(tune2fs -l "$DEV" 2>/dev/null | grep 'Filesystem features' || true)"
    echo "[wowOS] Cannot grow filesystem; check e2fsprogs version (need >= 1.47 for orphan_file feature)."
    exit 1
  fi
}

mkdir -p /mnt/wowos
if [ -b "${LOOP_DEV}p2" ]; then
  if [ "$NEED_RESIZE" = "1" ]; then
    grow_root_fs "${LOOP_DEV}p2"
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
    grow_root_fs "/dev/mapper/${MAPPER}p2"
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
chroot /mnt/wowos apt-get install -y --no-install-recommends \
  python3 python3-pip python3-venv sqlite3 \
  lightdm lightdm-gtk-greeter xserver-xorg xinit openbox \
  xserver-xorg-input-libinput xserver-xorg-video-fbdev libgl1-mesa-dri \
  chromium unclutter curl \
  dbus-x11 x11-xserver-utils \
  network-manager \
  fonts-wqy-microhei
chroot /mnt/wowos apt-get clean
chroot /mnt/wowos rm -rf /var/lib/apt/lists/*

# 4. Create wowos service user/group (API runs as this user) and desktop user
chroot /mnt/wowos groupadd -r wowos 2>/dev/null || true
chroot /mnt/wowos useradd -r -s /bin/false -g wowos -d /var/lib/wowos wowos 2>/dev/null || true
chroot /mnt/wowos id admin >/dev/null 2>&1 || chroot /mnt/wowos useradd -m -s /bin/bash admin
chroot /mnt/wowos usermod -aG video,input admin 2>/dev/null || true

# 5. Copy wowOS core and desktop UI
mkdir -p /mnt/wowos/opt/wowos
cp -r "$PROJECT_ROOT/wowos_core" /mnt/wowos/opt/wowos/
cp -r "$PROJECT_ROOT/config" /mnt/wowos/opt/wowos/
cp -r "$PROJECT_ROOT/ui" /mnt/wowos/opt/wowos/ 2>/dev/null || true
cp "$PROJECT_ROOT/requirements.txt" /mnt/wowos/opt/wowos/ 2>/dev/null || true
chroot /mnt/wowos chown -R wowos:wowos /opt/wowos

# 5b. Install Python dependencies from requirements.txt inside the image
if [ -f "$PROJECT_ROOT/requirements.txt" ]; then
  chroot /mnt/wowos python3 -m pip install --break-system-packages --no-cache-dir -r /opt/wowos/requirements.txt
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

# 8b. Verify critical boot files are present (missing files mean the Pi won't recognise the card)
echo "[wowOS] Verifying boot partition files..."
BOOT_OK=1
for BOOTFILE in config.txt cmdline.txt; do
  if [ ! -f "/mnt/wowos/boot/$BOOTFILE" ]; then
    echo "[wowOS] ERROR: Required boot file missing: /boot/$BOOTFILE"
    BOOT_OK=0
  fi
done
if [ "$BOOT_OK" = "0" ]; then
  echo "[wowOS] The boot partition is incomplete. The base image download may be corrupted."
  echo "[wowOS] Delete $IMG_NAME and re-run to download a fresh copy."
  exit 1
fi
echo "[wowOS] Boot partition OK: config.txt and cmdline.txt present."

# 8c. Ensure GPU has enough memory for graphical desktop + Chromium kiosk
if ! grep -q '^gpu_mem=' /mnt/wowos/boot/config.txt 2>/dev/null; then
  echo "[wowOS] Adding gpu_mem=128 to config.txt for graphical desktop"
  printf '\n# wowOS: ensure enough GPU memory for desktop + kiosk\ngpu_mem=128\n' >> /mnt/wowos/boot/config.txt
fi

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
greeter-session=lightdm-gtk-greeter
EOF

# Openbox autostart: display settings only; kiosk is launched by wowos-kiosk.service
mkdir -p /mnt/wowos/home/admin/.config/openbox
cat > /mnt/wowos/home/admin/.config/openbox/autostart << 'EOF'
xset -dpms
xset s off
xset s noblank
unclutter -idle 0.5 -root >/dev/null 2>&1 &
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

# 10b. Shrink root filesystem and image to minimum size so the image fits on standard SD cards.
#      On first boot Raspberry Pi OS automatically expands the root partition to fill the card.
if [ -b "${LOOP_DEV}p2" ]; then
  ROOT_PART="${LOOP_DEV}p2"
else
  ROOT_PART="/dev/mapper/$(basename "$LOOP_DEV")p2"
fi
echo "[wowOS] Shrinking root filesystem to minimum (image will auto-expand on first boot)..."
e2fsck -f -y "$ROOT_PART" || true
resize2fs -M "$ROOT_PART"

# Calculate new partition end: partition-2 start + shrunken fs size + 64 MB padding
FS_BLOCK_COUNT=$(tune2fs -l "$ROOT_PART" 2>/dev/null | awk '/^Block count:/{print $3}')
FS_BLOCK_SIZE=$(tune2fs -l "$ROOT_PART" 2>/dev/null | awk '/^Block size:/{print $3}')
PART2_START_SECTORS=$(parted -s "$LOOP_DEV" unit s print 2>/dev/null | awk '/^ *2 /{gsub(/s/,"",$2); print $2}')
SECTOR_SIZE=512
PART2_START_BYTES=$(( PART2_START_SECTORS * SECTOR_SIZE ))
FS_BYTES=$(( FS_BLOCK_COUNT * FS_BLOCK_SIZE ))
NEW_END_BYTES=$(( PART2_START_BYTES + FS_BYTES + 64 * 1024 * 1024 ))
NEW_END_MiB=$(( NEW_END_BYTES / 1024 / 1024 + 2 ))  # +2 MiB for partition alignment
echo "[wowOS] Shrinking partition 2 end to ${NEW_END_MiB}MiB..."
parted -s "$LOOP_DEV" resizepart 2 ${NEW_END_MiB}MiB || true

if [ -b "${LOOP_DEV}p2" ]; then
  losetup -d "$LOOP_DEV"
else
  kpartx -dv "$LOOP_DEV"
  losetup -d "$LOOP_DEV"
fi

# Truncate the image file to remove all unused space (+4 MiB trailing buffer for firmware safety margin)
NEW_IMG_BYTES=$(( (NEW_END_MiB + 4) * 1024 * 1024 ))
truncate -s "$NEW_IMG_BYTES" "$IMG_NAME"
echo "[wowOS] Final image size: $(du -sh "$IMG_NAME" | cut -f1)"

# Fix partition table after truncation to prevent "no valid partition table" errors on Pi firmware.
# For MBR images: parted rewrites the table cleanly; for GPT images: sgdisk relocates the backup header.
LOOP_FINAL=$(losetup -f --show -P "$IMG_NAME" 2>/dev/null) || LOOP_FINAL=$(losetup -f --show "$IMG_NAME")
if [ -n "$LOOP_FINAL" ]; then
  partprobe "$LOOP_FINAL" 2>/dev/null || true
  if command -v sgdisk >/dev/null 2>&1; then
    sgdisk -e "$LOOP_FINAL" 2>/dev/null || true   # relocate GPT backup header to end of image
  fi
  parted -s "$LOOP_FINAL" print 2>/dev/null || true  # rewrite MBR/GPT cleanly
  losetup -d "$LOOP_FINAL" 2>/dev/null || true
fi

rmdir /mnt/wowos 2>/dev/null || true

# 11. Zip
zip -q "wowos-${WOWOS_VERSION}.img.zip" "$IMG_NAME"
echo "[wowOS] Done: wowos-${WOWOS_VERSION}.img.zip"
echo "[wowOS] Flash to SD, boot Pi; SSH enabled, API on port 8080. Optional: run wowos-firstboot to set device password."
