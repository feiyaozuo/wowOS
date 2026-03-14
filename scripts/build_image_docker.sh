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
    chroot /mnt/wowos apt-get install -y -qq --no-install-recommends \
      python3 python3-pip python3-venv sqlite3 \
      lightdm lightdm-gtk-greeter xserver-xorg xinit openbox \
      xserver-xorg-input-libinput xserver-xorg-video-fbdev libgl1-mesa-dri \
      chromium unclutter curl \
      dbus-x11 x11-xserver-utils \
      network-manager \
      fonts-wqy-microhei
    chroot /mnt/wowos apt-get clean
    chroot /mnt/wowos rm -rf /var/lib/apt/lists/*

    # 4. Users: wowos service user + desktop admin user
    chroot /mnt/wowos groupadd -r wowos 2>/dev/null || true
    chroot /mnt/wowos useradd -r -s /bin/false -g wowos -d /var/lib/wowos wowos 2>/dev/null || true
    chroot /mnt/wowos id admin >/dev/null 2>&1 || chroot /mnt/wowos useradd -m -s /bin/bash admin
    chroot /mnt/wowos usermod -aG video,input admin 2>/dev/null || true

    # 5. Copy code
    mkdir -p /mnt/wowos/opt/wowos
    cp -r /wowos/wowos_core /mnt/wowos/opt/wowos/
    cp -r /wowos/config /mnt/wowos/opt/wowos/
    cp -r /wowos/ui /mnt/wowos/opt/wowos/ 2>/dev/null || true
    cp /wowos/requirements.txt /mnt/wowos/opt/wowos/ 2>/dev/null || true
    chroot /mnt/wowos chown -R wowos:wowos /opt/wowos

    # 5b. Install Python deps from requirements.txt inside the image
    if [ -f /wowos/requirements.txt ]; then
      chroot /mnt/wowos python3 -m pip install --break-system-packages --no-cache-dir -r /opt/wowos/requirements.txt
    fi

    # 6. systemd
    cp /wowos/services/wowos-api.service /mnt/wowos/etc/systemd/system/
    cp /wowos/services/wowos-desktop.service /mnt/wowos/etc/systemd/system/ 2>/dev/null || true
    cp /wowos/services/wowos-kiosk.service /mnt/wowos/etc/systemd/system/
    chroot /mnt/wowos systemctl enable wowos-api.service
    chroot /mnt/wowos systemctl enable wowos-desktop.service 2>/dev/null || true

    # 7. Data dirs
    chroot /mnt/wowos mkdir -p /var/lib/wowos /data/files /data/apps
    chroot /mnt/wowos chown -R wowos:wowos /var/lib/wowos /data
    chroot /mnt/wowos chmod 751 /data
    chroot /mnt/wowos chmod 700 /data/files
    chroot /mnt/wowos chmod 751 /data/apps

    # 8. SSH
    touch /mnt/wowos/boot/ssh

    # 8b. Ensure GPU has enough memory for graphical desktop + Chromium kiosk
    if ! grep -q "^gpu_mem=" /mnt/wowos/boot/config.txt 2>/dev/null; then
      echo "[wowOS] Adding gpu_mem=128 to config.txt for graphical desktop"
      printf "\n# wowOS: ensure enough GPU memory for desktop + kiosk\ngpu_mem=128\n" >> /mnt/wowos/boot/config.txt
    fi

    # 9b. Desktop & kiosk — scripts + LightDM autologin + Openbox autostart
    mkdir -p /mnt/wowos/opt/wowos/scripts
    cp /wowos/scripts/start_kiosk.sh /mnt/wowos/opt/wowos/scripts/
    chroot /mnt/wowos chmod +x /opt/wowos/scripts/start_kiosk.sh

    chroot /mnt/wowos mkdir -p /etc/lightdm/lightdm.conf.d
    cat > /mnt/wowos/etc/lightdm/lightdm.conf.d/50-wowos-autologin.conf << "EOF"
[Seat:*]
autologin-user=admin
autologin-user-timeout=0
user-session=openbox
greeter-session=lightdm-gtk-greeter
EOF

    mkdir -p /mnt/wowos/home/admin/.config/openbox
    cat > /mnt/wowos/home/admin/.config/openbox/autostart << "EOF"
xset -dpms
xset s off
xset s noblank
unclutter -idle 0.5 -root >/dev/null 2>&1 &
EOF
    chroot /mnt/wowos chown -R admin:admin /home/admin/.config

    # Enable services and graphical target
    chroot /mnt/wowos systemctl enable lightdm
    chroot /mnt/wowos systemctl enable wowos-api.service
    chroot /mnt/wowos systemctl enable wowos-desktop.service 2>/dev/null || true
    chroot /mnt/wowos systemctl enable wowos-kiosk.service
    chroot /mnt/wowos systemctl set-default graphical.target

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
