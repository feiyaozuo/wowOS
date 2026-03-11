#!/bin/bash
# wowOS 首次启动向导：设置管理员密码、设备密钥相关环境（可选）
# 可在镜像中配置为首次登录时运行，或由 systemd 在 first-boot 时执行一次
set -e
CONFIG_DIR="${VAR_LIB_WOWOS:-/var/lib/wowos}"
mkdir -p "$CONFIG_DIR"

echo "=== wowOS 首次启动向导 ==="
echo "本脚本用于设置设备密码（用于密钥派生），并写入环境配置。"

read -sp "请输入设备密码（用于加密密钥派生，留空则使用默认）: " DEVICE_PASS
echo
if [ -n "$DEVICE_PASS" ]; then
  echo "WOWOS_DEVICE_PASSWORD=$DEVICE_PASS" >> "$CONFIG_DIR/env"
  chmod 600 "$CONFIG_DIR/env"
  echo "已保存到 $CONFIG_DIR/env"
fi

# 可选：从 /sys/class/net/eth0/address 读取的 device_id 已由 crypto_engine 自动使用
echo "完成。启动 API 服务: systemctl start wowos-api"
