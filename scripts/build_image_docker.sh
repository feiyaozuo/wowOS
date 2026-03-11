#!/bin/bash
# Build wowOS image inside Docker (for macOS or when losetup is not available)
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/build}"
mkdir -p "$BUILD_DIR"

echo "[wowOS] Building image inside Docker (Linux container)..."
echo "[wowOS] Build output dir: $BUILD_DIR"

docker run --rm --privileged \
  -v "$PROJECT_ROOT:/wowos:rw" \
  -e BUILD_DIR=/wowos/build \
  -e IMG_NAME=raspios-lite.img \
  -e WOWOS_VERSION=1.0 \
  -w /wowos \
  ubuntu:22.04 \
  bash -c '
    set -e
    apt-get update -qq
    apt-get install -y -qq util-linux mount kpartx wget zip python3 python3-pip sqlite3 > /dev/null
    # Install Python deps via pip (no raspios in container; for placeholder build test)
    python3 -m pip install --break-system-packages flask pyjwt cryptography pyyaml requests 2>/dev/null || true
    export BUILD_DIR=/wowos/build
    export IMG_NAME=raspios-lite.img
    export WOWOS_VERSION=1.0
    cd "$BUILD_DIR"

    # 1. Download base image
    if [ ! -f "$IMG_NAME" ]; then
      echo "[wowOS] Downloading Raspberry Pi OS Lite (arm64)..."
      wget -q --show-progress "https://downloads.raspberrypi.org/raspios_lite_arm64_latest" -O "$IMG_NAME" || true
      if [ ! -f "$IMG_NAME" ]; then
        echo "[wowOS] Download failed; create build dir and place raspios_lite_arm64 image as $IMG_NAME"
        exit 1
      fi
    fi

    # 2. Mount
    LOOP_DEV=$(losetup -f --show -P "$IMG_NAME")
    echo "[wowOS] Loop: $LOOP_DEV"
    mkdir -p /mnt/wowos
    mount "${LOOP_DEV}p2" /mnt/wowos
    mount "${LOOP_DEV}p1" /mnt/wowos/boot

    # 3. chroot install deps (use host resolv.conf so chroot has network)
    mount --bind /dev /mnt/wowos/dev
    mount --bind /proc /mnt/wowos/proc
    mount --bind /sys /mnt/wowos/sys
    cp /etc/resolv.conf /mnt/wowos/etc/resolv.conf
    chroot /mnt/wowos apt-get update -qq
    chroot /mnt/wowos apt-get install -y -qq python3 python3-pip sqlite3
    chroot /mnt/wowos python3 -m pip install --break-system-packages flask pyjwt cryptography pyyaml requests

    # 4. User
    chroot /mnt/wowos groupadd -r wowos 2>/dev/null || true
    chroot /mnt/wowos useradd -r -s /bin/false -g wowos -d /var/lib/wowos wowos 2>/dev/null || true

    # 5. Copy code
    mkdir -p /mnt/wowos/opt/wowos
    cp -r /wowos/wowos_core /mnt/wowos/opt/wowos/
    cp -r /wowos/config /mnt/wowos/opt/wowos/
    cp /wowos/requirements.txt /mnt/wowos/opt/wowos/ 2>/dev/null || true
    chroot /mnt/wowos chown -R wowos:wowos /opt/wowos

    # 6. systemd
    cp /wowos/services/wowos-api.service /mnt/wowos/etc/systemd/system/
    chroot /mnt/wowos systemctl enable wowos-api.service

    # 7. Data dirs
    chroot /mnt/wowos mkdir -p /var/lib/wowos /data/files /data/apps
    chroot /mnt/wowos chown -R wowos:wowos /var/lib/wowos /data
    chroot /mnt/wowos chmod 751 /data
    chroot /mnt/wowos chmod 700 /data/files
    chroot /mnt/wowos chmod 751 /data/apps

    # 8. SSH
    touch /mnt/wowos/boot/ssh

    # 9. First-boot script
    cp /wowos/scripts/firstboot_wizard.sh /mnt/wowos/usr/local/bin/wowos-firstboot 2>/dev/null || true
    chroot /mnt/wowos chmod +x /usr/local/bin/wowos-firstboot 2>/dev/null || true

    # 10. Unmount
    umount /mnt/wowos/dev /mnt/wowos/proc /mnt/wowos/sys
    umount /mnt/wowos/boot /mnt/wowos
    losetup -d "$LOOP_DEV"
    rmdir /mnt/wowos 2>/dev/null || true

    # 11. Zip
    zip -q "/wowos/build/wowos-${WOWOS_VERSION}.img.zip" "$IMG_NAME"
    echo "[wowOS] Done: /wowos/build/wowos-${WOWOS_VERSION}.img.zip"
  '

echo "[wowOS] Image built: $BUILD_DIR/wowos-1.0.img.zip"
