#!/bin/bash
# wowOS first-boot wizard: generate device salt, set device password and token secret, write env for service
# Can be run on first login or by systemd once on first-boot
set -e
CONFIG_DIR="${VAR_LIB_WOWOS:-/var/lib/wowos}"
SALT_FILE="$CONFIG_DIR/device_salt"
ENV_FILE="$CONFIG_DIR/env"
mkdir -p "$CONFIG_DIR"

echo "=== wowOS First-Boot Wizard ==="

# 1. Per-device salt (generate once)
if [ ! -f "$SALT_FILE" ]; then
  echo "Generating device salt: $SALT_FILE"
  head -c 32 /dev/urandom | base64 -w0 > "$SALT_FILE"
  chmod 600 "$SALT_FILE"
fi

# 2. Device password (used to derive data encryption master key)
read -sp "Enter device password (for key derivation, required): " DEVICE_PASS
echo
if [ -z "$DEVICE_PASS" ]; then
  echo "No password set; using default (dev only). For production, run again and set a password."
  DEVICE_PASS="user_supplied"
fi

# 3. Env file: keep existing keys or generate; write/update WOWOS_DEVICE_PASSWORD and WOWOS_ADMIN_TOKEN
if [ -f "$ENV_FILE" ]; then
  SECRET_KEY=$(grep -E '^WOWOS_SECRET_KEY=' "$ENV_FILE" | cut -d= -f2- || true)
  ADMIN_TOKEN=$(grep -E '^WOWOS_ADMIN_TOKEN=' "$ENV_FILE" | cut -d= -f2- || true)
fi
if [ -z "$SECRET_KEY" ]; then
  SECRET_KEY=$(openssl rand -base64 32 2>/dev/null || head -c 32 /dev/urandom | base64 -w0)
fi
if [ -z "$ADMIN_TOKEN" ]; then
  ADMIN_TOKEN=$(openssl rand -hex 24 2>/dev/null || head -c 24 /dev/urandom | xxd -p -c 256)
fi
{
  echo "WOWOS_SECRET_KEY=$SECRET_KEY"
  echo "WOWOS_DEVICE_PASSWORD=$DEVICE_PASS"
  echo "WOWOS_ADMIN_TOKEN=$ADMIN_TOKEN"
} > "$ENV_FILE"
chmod 600 "$ENV_FILE"

echo "Written to $ENV_FILE (WOWOS_SECRET_KEY, WOWOS_DEVICE_PASSWORD, WOWOS_ADMIN_TOKEN)"
echo "Save WOWOS_ADMIN_TOKEN for calling /api/v1/tokens and /api/v1/audit."
echo "Done. Start API: systemctl start wowos-api"
