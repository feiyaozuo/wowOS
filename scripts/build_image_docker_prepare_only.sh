#!/bin/bash
# Prepare-only build inside Docker: no chroot apt, only copy code and add user. After flash run install-deps once on Pi.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/build}"
mkdir -p "$BUILD_DIR"

docker run --rm --privileged \
  -v "$PROJECT_ROOT:/wowos:rw" \
  -w /wowos \
  ubuntu:22.04 \
  bash -c '
    set -e
    apt-get update -qq && apt-get install -y -qq util-linux wget zip xz-utils file kpartx > /dev/null
    BUILD_DIR=/wowos/build
    cd "$BUILD_DIR"
    IMG_NAME=raspios-lite.img
    if [ ! -f "$IMG_NAME" ]; then
      echo "[wowOS] Downloading Raspberry Pi OS Lite (arm64)..."
      wget -L -q --show-progress "https://downloads.raspberrypi.org/raspios_lite_arm64_latest" -O raspios-dl || true
      if [ -f raspios-dl ]; then
        if file raspios-dl | grep -qi "XZ"; then
          xz -d -c raspios-dl > "$IMG_NAME" && rm -f raspios-dl
        elif file raspios-dl | grep -qi "gzip"; then
          gzip -d -c raspios-dl > "$IMG_NAME" && rm -f raspios-dl
        else
          mv raspios-dl "$IMG_NAME"
        fi
      fi
    fi
    if [ ! -f "$IMG_NAME" ]; then
      echo "[wowOS] Put base image at build/raspios-lite.img (raw .img)"
      exit 1
    fi
    if file "$IMG_NAME" | grep -qi "XZ compressed"; then
      echo "[wowOS] Decompressing xz to raw image..."
      xz -d -c "$IMG_NAME" > "${IMG_NAME}.tmp" && mv "${IMG_NAME}.tmp" "$IMG_NAME"
    fi
    LOOP_DEV=$(losetup -f --show -P "$IMG_NAME" 2>/dev/null) || LOOP_DEV=$(losetup -f --show "$IMG_NAME")
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
    WOWOS_UID=999
    WOWOS_GID=999
    echo "wowos:x:${WOWOS_GID}:" >> /mnt/wowos/etc/group
    echo "wowos:x:${WOWOS_UID}:${WOWOS_GID}:wowOS service:/var/lib/wowos:/bin/false" >> /mnt/wowos/etc/passwd
    mkdir -p /mnt/wowos/opt/wowos /mnt/wowos/var/lib/wowos /mnt/wowos/data/files /mnt/wowos/data/apps
    cp -r /wowos/wowos_core /mnt/wowos/opt/wowos/
    cp -r /wowos/config /mnt/wowos/opt/wowos/
    cp -r /wowos/ui /mnt/wowos/opt/wowos/ 2>/dev/null || true
    cp /wowos/requirements.txt /mnt/wowos/opt/wowos/ 2>/dev/null || true
    chown -R ${WOWOS_UID}:${WOWOS_GID} /mnt/wowos/opt/wowos /mnt/wowos/var/lib/wowos /mnt/wowos/data
    chmod 751 /mnt/wowos/data
    chmod 700 /mnt/wowos/data/files
    chmod 751 /mnt/wowos/data/apps
    cp /wowos/services/wowos-api.service /mnt/wowos/etc/systemd/system/
    cp /wowos/services/wowos-desktop.service /mnt/wowos/etc/systemd/system/ 2>/dev/null || true
    mkdir -p /mnt/wowos/etc/systemd/system/multi-user.target.wants
    ln -sf ../wowos-desktop.service /mnt/wowos/etc/systemd/system/multi-user.target.wants/wowos-desktop.service 2>/dev/null || true
    touch /mnt/wowos/boot/ssh
    # Ensure GPU has enough memory for graphical desktop + Chromium kiosk
    if ! grep -q "^gpu_mem=" /mnt/wowos/boot/config.txt 2>/dev/null; then
      printf "\n# wowOS: ensure enough GPU memory for desktop + kiosk\ngpu_mem=128\n" >> /mnt/wowos/boot/config.txt
    fi
    # 方案2：桌面与 kiosk — 脚本放到 /opt/wowos/scripts/
    mkdir -p /mnt/wowos/opt/wowos/scripts
    cp /wowos/scripts/install_desktop_once.sh /mnt/wowos/opt/wowos/scripts/
    cp /wowos/scripts/start_kiosk.sh /mnt/wowos/opt/wowos/scripts/
    chmod +x /mnt/wowos/opt/wowos/scripts/install_desktop_once.sh /mnt/wowos/opt/wowos/scripts/start_kiosk.sh
    cp /wowos/services/wowos-install-desktop-once.service /mnt/wowos/etc/systemd/system/
    cp /wowos/services/wowos-kiosk.service /mnt/wowos/etc/systemd/system/
    mkdir -p /mnt/wowos/etc/systemd/system/multi-user.target.wants
    ln -sf ../wowos-install-desktop-once.service /mnt/wowos/etc/systemd/system/multi-user.target.wants/wowos-install-desktop-once.service 2>/dev/null || true
    mkdir -p /mnt/wowos/etc/systemd/system/graphical.target.wants
    ln -sf ../wowos-kiosk.service /mnt/wowos/etc/systemd/system/graphical.target.wants/wowos-kiosk.service 2>/dev/null || true
    umount /mnt/wowos/boot /mnt/wowos
    if [ -b "${LOOP_DEV}p2" ]; then
      losetup -d "$LOOP_DEV"
    else
      kpartx -dv "$LOOP_DEV"
      losetup -d "$LOOP_DEV"
    fi
    rmdir /mnt/wowos 2>/dev/null || true
    zip -q /wowos/build/wowos-1.0.img.zip "$IMG_NAME"
    echo "[wowOS] Done: build/wowos-1.0.img.zip (prepare-only, 方案2)"
    echo "[wowOS] After flash: first boot runs wowos-install-desktop-once; reboot to enter graphical + kiosk."
  '
echo "[wowOS] Image: $BUILD_DIR/wowos-1.0.img.zip"
