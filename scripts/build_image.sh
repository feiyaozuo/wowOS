#!/bin/bash
# 基于 Raspberry Pi OS Lite 构建 wowOS 镜像（需 root 或 sudo）
# 使用前：建议在 Linux 下执行，或通过 Docker/VM 提供 losetup、mount、chroot
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${BUILD_DIR:-/tmp/wowos-build}"
IMG_NAME="${IMG_NAME:-raspios-lite.img}"
WOWOS_VERSION="${WOWOS_VERSION:-1.0}"

echo "[wowOS] Build dir: $BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# 1. 下载基础镜像（若不存在）
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

# 2. 挂载镜像（需要 root）
LOOP_DEV=$(losetup -f --show -P "$IMG_NAME")
echo "[wowOS] Loop device: $LOOP_DEV"
mkdir -p /mnt/wowos
mount "${LOOP_DEV}p2" /mnt/wowos
mount "${LOOP_DEV}p1" /mnt/wowos/boot

# 3. chroot 安装依赖
mount --bind /dev /mnt/wowos/dev
mount --bind /proc /mnt/wowos/proc
mount --bind /sys /mnt/wowos/sys
chroot /mnt/wowos apt-get update
chroot /mnt/wowos apt-get install -y python3 python3-pip sqlite3
chroot /mnt/wowos python3 -m pip install --break-system-packages flask pyjwt cryptography pyyaml requests

# 4. 创建 wowos 用户/组（API 服务以此用户运行）
chroot /mnt/wowos groupadd -r wowos 2>/dev/null || true
chroot /mnt/wowos useradd -r -s /bin/false -g wowos -d /var/lib/wowos wowos 2>/dev/null || true

# 5. 复制 wowOS 核心代码
mkdir -p /mnt/wowos/opt/wowos
cp -r "$PROJECT_ROOT/wowos_core" /mnt/wowos/opt/wowos/
cp -r "$PROJECT_ROOT/config" /mnt/wowos/opt/wowos/
cp "$PROJECT_ROOT/requirements.txt" /mnt/wowos/opt/wowos/ 2>/dev/null || true
chroot /mnt/wowos chown -R wowos:wowos /opt/wowos

# 6. systemd 服务
cp "$PROJECT_ROOT/services/wowos-api.service" /mnt/wowos/etc/systemd/system/
chroot /mnt/wowos systemctl enable wowos-api.service

# 7. 数据与配置目录（归属 wowos，服务可写）
chroot /mnt/wowos mkdir -p /var/lib/wowos /data/files
chroot /mnt/wowos chown -R wowos:wowos /var/lib/wowos /data

# 8. 启用 SSH（烧录后无头可用；Raspberry Pi OS 以 boot 分区存在 ssh 文件即开启）
touch /mnt/wowos/boot/ssh

# 9. 首次启动脚本（可登录后手动执行 wowos-firstboot 设置设备密码）
cp "$PROJECT_ROOT/scripts/firstboot_wizard.sh" /mnt/wowos/usr/local/bin/wowos-firstboot 2>/dev/null || true
chroot /mnt/wowos chmod +x /usr/local/bin/wowos-firstboot 2>/dev/null || true

# 10. 卸载
umount /mnt/wowos/dev /mnt/wowos/proc /mnt/wowos/sys
umount /mnt/wowos/boot /mnt/wowos
losetup -d "$LOOP_DEV"
rmdir /mnt/wowos 2>/dev/null || true

# 11. 压缩
zip -q "wowos-${WOWOS_VERSION}.img.zip" "$IMG_NAME"
echo "[wowOS] Done: wowos-${WOWOS_VERSION}.img.zip"
echo "[wowOS] Flash to SD, boot Pi; SSH enabled, API on port 8080. Optional: run wowos-firstboot to set device password."
