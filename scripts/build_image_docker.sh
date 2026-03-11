#!/bin/bash
# 在 Docker 内构建 wowOS 镜像（适用于 macOS 或无法直接使用 losetup 的环境）
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
    # 使用 pip 安装 Python 依赖（镜像内无 raspios，仅做占位构建测试时可用）
    python3 -m pip install --break-system-packages flask pyjwt cryptography pyyaml requests 2>/dev/null || true
    export BUILD_DIR=/wowos/build
    export IMG_NAME=raspios-lite.img
    export WOWOS_VERSION=1.0
    cd "$BUILD_DIR"

    # 1. 下载基础镜像
    if [ ! -f "$IMG_NAME" ]; then
      echo "[wowOS] Downloading Raspberry Pi OS Lite (arm64)..."
      wget -q --show-progress "https://downloads.raspberrypi.org/raspios_lite_arm64_latest" -O "$IMG_NAME" || true
      if [ ! -f "$IMG_NAME" ]; then
        echo "[wowOS] Download failed; create build dir and place raspios_lite_arm64 image as $IMG_NAME"
        exit 1
      fi
    fi

    # 2. 挂载
    LOOP_DEV=$(losetup -f --show -P "$IMG_NAME")
    echo "[wowOS] Loop: $LOOP_DEV"
    mkdir -p /mnt/wowos
    mount "${LOOP_DEV}p2" /mnt/wowos
    mount "${LOOP_DEV}p1" /mnt/wowos/boot

    # 3. chroot 安装依赖（使用宿主机 resolv.conf 保证 chroot 内可联网）
    mount --bind /dev /mnt/wowos/dev
    mount --bind /proc /mnt/wowos/proc
    mount --bind /sys /mnt/wowos/sys
    cp /etc/resolv.conf /mnt/wowos/etc/resolv.conf
    chroot /mnt/wowos apt-get update -qq
    chroot /mnt/wowos apt-get install -y -qq python3 python3-pip sqlite3
    chroot /mnt/wowos python3 -m pip install --break-system-packages flask pyjwt cryptography pyyaml requests

    # 4. 用户
    chroot /mnt/wowos groupadd -r wowos 2>/dev/null || true
    chroot /mnt/wowos useradd -r -s /bin/false -g wowos -d /var/lib/wowos wowos 2>/dev/null || true

    # 5. 复制代码
    mkdir -p /mnt/wowos/opt/wowos
    cp -r /wowos/wowos_core /mnt/wowos/opt/wowos/
    cp -r /wowos/config /mnt/wowos/opt/wowos/
    cp /wowos/requirements.txt /mnt/wowos/opt/wowos/ 2>/dev/null || true
    chroot /mnt/wowos chown -R wowos:wowos /opt/wowos

    # 6. systemd
    cp /wowos/services/wowos-api.service /mnt/wowos/etc/systemd/system/
    chroot /mnt/wowos systemctl enable wowos-api.service

    # 7. 数据目录
    chroot /mnt/wowos mkdir -p /var/lib/wowos /data/files
    chroot /mnt/wowos chown -R wowos:wowos /var/lib/wowos /data

    # 8. SSH
    touch /mnt/wowos/boot/ssh

    # 9. 首次启动脚本
    cp /wowos/scripts/firstboot_wizard.sh /mnt/wowos/usr/local/bin/wowos-firstboot 2>/dev/null || true
    chroot /mnt/wowos chmod +x /usr/local/bin/wowos-firstboot 2>/dev/null || true

    # 10. 卸载
    umount /mnt/wowos/dev /mnt/wowos/proc /mnt/wowos/sys
    umount /mnt/wowos/boot /mnt/wowos
    losetup -d "$LOOP_DEV"
    rmdir /mnt/wowos 2>/dev/null || true

    # 11. 压缩
    zip -q "/wowos/build/wowos-${WOWOS_VERSION}.img.zip" "$IMG_NAME"
    echo "[wowOS] Done: /wowos/build/wowos-${WOWOS_VERSION}.img.zip"
  '

echo "[wowOS] Image built: $BUILD_DIR/wowos-1.0.img.zip"
