#!/bin/bash
# 仅准备镜像：挂载后复制 wowOS 代码、创建用户、配置 systemd，不执行 chroot apt-get。
# 适用于无外网或 Docker 内 chroot 无法拉包的环境。烧录后首次启动需在树莓派上执行一次：
#   sudo apt update && sudo apt install -y python3 python3-pip sqlite3
#   sudo python3 -m pip install --break-system-packages flask pyjwt cryptography pyyaml requests
# 然后 systemctl start wowos-api
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
  wget -q --show-progress "https://downloads.raspberrypi.org/raspios_lite_arm64_latest" -O "$IMG_NAME" || true
  if [ ! -f "$IMG_NAME" ]; then
    echo "[wowOS] Put Raspberry Pi OS Lite arm64 image at $BUILD_DIR/$IMG_NAME"
    exit 1
  fi
fi

LOOP_DEV=$(losetup -f --show -P "$IMG_NAME")
echo "[wowOS] Loop: $LOOP_DEV"
mkdir -p /mnt/wowos
mount "${LOOP_DEV}p2" /mnt/wowos
mount "${LOOP_DEV}p1" /mnt/wowos/boot

# 在镜像内添加 wowos 用户（直接写 passwd/group）
echo "wowos:x:${WOWOS_GID}:" >> /mnt/wowos/etc/group
echo "wowos:x:${WOWOS_UID}:${WOWOS_GID}:wowOS service:/var/lib/wowos:/bin/false" >> /mnt/wowos/etc/passwd
mkdir -p /mnt/wowos/opt/wowos /mnt/wowos/var/lib/wowos /mnt/wowos/data/files
cp -r "$PROJECT_ROOT/wowos_core" /mnt/wowos/opt/wowos/
cp -r "$PROJECT_ROOT/config" /mnt/wowos/opt/wowos/
cp "$PROJECT_ROOT/requirements.txt" /mnt/wowos/opt/wowos/ 2>/dev/null || true
chown -R ${WOWOS_UID}:${WOWOS_GID} /mnt/wowos/opt/wowos /mnt/wowos/var/lib/wowos /mnt/wowos/data
cp "$PROJECT_ROOT/services/wowos-api.service" /mnt/wowos/etc/systemd/system/
touch /mnt/wowos/boot/ssh
cp "$PROJECT_ROOT/scripts/firstboot_wizard.sh" /mnt/wowos/usr/local/bin/wowos-firstboot 2>/dev/null || true
chmod +x /mnt/wowos/usr/local/bin/wowos-firstboot 2>/dev/null || true

# 写入首次启动安装依赖的说明
mkdir -p /mnt/wowos/root
cat > /mnt/wowos/root/wowos-firstboot-install.sh << 'INNER'
#!/bin/bash
# 在树莓派上首次启动后以 root 执行一次
apt-get update && apt-get install -y python3 python3-pip sqlite3
python3 -m pip install --break-system-packages flask pyjwt cryptography pyyaml requests
systemctl start wowos-api
echo "wowOS API should be running on port 8080."
INNER
chmod +x /mnt/wowos/root/wowos-firstboot-install.sh

umount /mnt/wowos/boot /mnt/wowos
losetup -d "$LOOP_DEV"
rmdir /mnt/wowos 2>/dev/null || true

zip -q "wowos-${WOWOS_VERSION}.img.zip" "$IMG_NAME"
echo "[wowOS] Done: wowos-${WOWOS_VERSION}.img.zip (prepare-only)"
echo "[wowOS] After flash, on the Pi run once: sudo /root/wowos-firstboot-install.sh"
echo "[wowOS] Or install deps manually and: systemctl start wowos-api"
echo "[wowOS] For full build (with deps in image), run ./scripts/build_image.sh on Linux with internet."
