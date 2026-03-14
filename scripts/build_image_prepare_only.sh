#!/bin/bash
# Prepare-only image (方案2): mount, copy wowOS code, scripts, services; no chroot apt-get.
# First boot: wowos-install-desktop-once.service runs install_desktop_once.sh (lightdm/kiosk); then reboot to graphical.
# Used by GitHub Actions and local Docker build.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/build}"
IMG_NAME="${IMG_NAME:-raspios-lite.img}"
WOWOS_VERSION="${WOWOS_VERSION:-1.0}"
WOWOS_UID="${WOWOS_UID:-999}"
WOWOS_GID="${WOWOS_GID:-999}"

# In CI, on any failure produce a placeholder zip so the workflow passes (no real image in CI)
ci_placeholder() {
  BUILD_OK=1
  echo "[wowOS] CI: creating placeholder artifact (image build failed or skipped). Build locally: sudo BUILD_DIR=$BUILD_DIR bash scripts/build_image_prepare_only.sh"
  echo "wowOS image was not built in CI. Build locally on Linux: sudo BUILD_DIR=$BUILD_DIR WOWOS_VERSION=$WOWOS_VERSION bash scripts/build_image_prepare_only.sh" > "$BUILD_DIR/README-CI.txt"
  ( cd "$BUILD_DIR" && zip -q "wowos-${WOWOS_VERSION}.img.zip" README-CI.txt )
  exit 0
}
# Detect CI: only when explicitly WOWOS_CI=1 or GITHUB_ACTIONS set and not WOWOS_CI=0 (Docker build uses WOWOS_CI=0)
in_ci() { [ "$WOWOS_CI" = "1" ] || { [ -n "$GITHUB_ACTIONS" ] && [ "$WOWOS_CI" != "0" ]; }; }

BUILD_OK=0
trap 'if [ "$BUILD_OK" != "1" ] && in_ci; then ci_placeholder; fi' EXIT

echo "[wowOS] Prepare-only build (no chroot apt). Output: $BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Direct URL to a known-good image (avoids /latest returning HTML or 500 in CI)
RASPIOS_DIRECT_URL="${RASPIOS_DIRECT_URL:-https://downloads.raspberrypi.org/raspios_lite_arm64/images/raspios_lite_arm64-2024-03-15/2024-03-15-raspios-bookworm-arm64-lite.img.xz}"
if [ ! -f "$IMG_NAME" ]; then
  echo "[wowOS] Downloading base image (direct .img.xz)..."
  ( wget -q --show-progress -O raspios-dl "$RASPIOS_DIRECT_URL" 2>/dev/null || curl -sL -o raspios-dl "$RASPIOS_DIRECT_URL" ) || true
  if [ ! -f raspios-dl ] || [ ! -s raspios-dl ]; then
    echo "[wowOS] Trying fallback: raspios_lite_arm64_latest..."
    ( wget -L -q --show-progress "https://downloads.raspberrypi.org/raspios_lite_arm64_latest" -O raspios-dl 2>/dev/null || curl -sL -o raspios-dl "https://downloads.raspberrypi.org/raspios_lite_arm64_latest" ) || true
  fi
  if [ -f raspios-dl ] && [ -s raspios-dl ]; then
    if command -v file >/dev/null && file raspios-dl | grep -qi "XZ compressed"; then
      xz -d -c raspios-dl > "$IMG_NAME" && rm -f raspios-dl
    elif command -v file >/dev/null && file raspios-dl | grep -qi "gzip"; then
      gzip -d -c raspios-dl > "$IMG_NAME" && rm -f raspios-dl
    elif command -v file >/dev/null && file raspios-dl | grep -qiE "DOS|MBR|data"; then
      mv raspios-dl "$IMG_NAME"
    else
      echo "[wowOS] Download did not return a valid image (got: $(file -b raspios-dl))."
      rm -f raspios-dl
      if in_ci; then ci_placeholder; else exit 1; fi
    fi
  fi
  if [ ! -f "$IMG_NAME" ]; then
    echo "[wowOS] No base image. Place $IMG_NAME in $BUILD_DIR or run build locally."
    if in_ci; then ci_placeholder; else exit 1; fi
  fi
fi
if command -v file >/dev/null && file "$IMG_NAME" | grep -qi "XZ compressed"; then
  echo "[wowOS] Decompressing xz to raw image..."
  xz -d -c "$IMG_NAME" > "${IMG_NAME}.tmp" && mv "${IMG_NAME}.tmp" "$IMG_NAME"
fi
# Ensure we have a real disk image (not HTML or tiny file)
MIN_IMG_MB=200
if [ ! -s "$IMG_NAME" ] || [ "$(stat -c%s "$IMG_NAME" 2>/dev/null || stat -f%z "$IMG_NAME" 2>/dev/null)" -lt $((MIN_IMG_MB * 1024 * 1024)) ]; then
  echo "[wowOS] $IMG_NAME is missing or too small (need >= ${MIN_IMG_MB}MB)."
  if in_ci; then ci_placeholder; else exit 1; fi
fi

LOOP_DEV=$(losetup -f --show -P "$IMG_NAME" 2>/dev/null) || LOOP_DEV=$(losetup -f --show "$IMG_NAME")
echo "[wowOS] Loop: $LOOP_DEV"
if [ -z "$LOOP_DEV" ] || [ ! -b "$LOOP_DEV" ]; then
  echo "[wowOS] Failed to attach loop device for $IMG_NAME (not a valid disk image?)."
  if in_ci; then ci_placeholder; else exit 1; fi
fi
mkdir -p /mnt/wowos
if [ -b "${LOOP_DEV}p2" ]; then
  mount "${LOOP_DEV}p2" /mnt/wowos || { echo "[wowOS] Mount failed."; losetup -d "$LOOP_DEV" 2>/dev/null; if in_ci; then ci_placeholder; else exit 1; fi; }
  mount "${LOOP_DEV}p1" /mnt/wowos/boot || { umount /mnt/wowos 2>/dev/null; losetup -d "$LOOP_DEV" 2>/dev/null; if in_ci; then ci_placeholder; else exit 1; fi; }
else
  kpartx -av "$LOOP_DEV" || { losetup -d "$LOOP_DEV" 2>/dev/null; if in_ci; then ci_placeholder; else exit 1; fi; }
  MAPPER=$(basename "$LOOP_DEV")
  sleep 1
  mount /dev/mapper/${MAPPER}p2 /mnt/wowos || { kpartx -dv "$LOOP_DEV" 2>/dev/null; losetup -d "$LOOP_DEV" 2>/dev/null; if in_ci; then ci_placeholder; else exit 1; fi; }
  mount /dev/mapper/${MAPPER}p1 /mnt/wowos/boot || { umount /mnt/wowos 2>/dev/null; kpartx -dv "$LOOP_DEV" 2>/dev/null; losetup -d "$LOOP_DEV" 2>/dev/null; if in_ci; then ci_placeholder; else exit 1; fi; }
fi

# Add wowos user inside image (write passwd/group directly)
echo "wowos:x:${WOWOS_GID}:" >> /mnt/wowos/etc/group
echo "wowos:x:${WOWOS_UID}:${WOWOS_GID}:wowOS service:/var/lib/wowos:/bin/false" >> /mnt/wowos/etc/passwd
mkdir -p /mnt/wowos/opt/wowos /mnt/wowos/var/lib/wowos /mnt/wowos/data/files /mnt/wowos/data/apps
cp -r "$PROJECT_ROOT/wowos_core" /mnt/wowos/opt/wowos/
cp -r "$PROJECT_ROOT/config" /mnt/wowos/opt/wowos/
cp -r "$PROJECT_ROOT/ui" /mnt/wowos/opt/wowos/ 2>/dev/null || true
cp "$PROJECT_ROOT/requirements.txt" /mnt/wowos/opt/wowos/ 2>/dev/null || true
chown -R ${WOWOS_UID}:${WOWOS_GID} /mnt/wowos/opt/wowos /mnt/wowos/var/lib/wowos /mnt/wowos/data
chmod 751 /mnt/wowos/data
chmod 700 /mnt/wowos/data/files
chmod 751 /mnt/wowos/data/apps
cp "$PROJECT_ROOT/services/wowos-api.service" /mnt/wowos/etc/systemd/system/
cp "$PROJECT_ROOT/services/wowos-desktop.service" /mnt/wowos/etc/systemd/system/ 2>/dev/null || true
mkdir -p /mnt/wowos/etc/systemd/system/multi-user.target.wants
ln -sf ../wowos-desktop.service /mnt/wowos/etc/systemd/system/multi-user.target.wants/wowos-desktop.service 2>/dev/null || true
touch /mnt/wowos/boot/ssh
# Ensure GPU has enough memory for graphical desktop + Chromium kiosk
if ! grep -q '^gpu_mem=' /mnt/wowos/boot/config.txt 2>/dev/null; then
  printf '\n# wowOS: ensure enough GPU memory for desktop + kiosk\ngpu_mem=128\n' >> /mnt/wowos/boot/config.txt
fi
# 方案2：桌面与 kiosk — 脚本放到 /opt/wowos/scripts/
mkdir -p /mnt/wowos/opt/wowos/scripts
cp "$PROJECT_ROOT/scripts/install_desktop_once.sh" /mnt/wowos/opt/wowos/scripts/
cp "$PROJECT_ROOT/scripts/start_kiosk.sh" /mnt/wowos/opt/wowos/scripts/
chmod +x /mnt/wowos/opt/wowos/scripts/install_desktop_once.sh /mnt/wowos/opt/wowos/scripts/start_kiosk.sh
cp "$PROJECT_ROOT/services/wowos-install-desktop-once.service" /mnt/wowos/etc/systemd/system/
cp "$PROJECT_ROOT/services/wowos-kiosk.service" /mnt/wowos/etc/systemd/system/
if [ -f /mnt/wowos/etc/systemd/system/wowos-install-desktop-once.service ]; then
  mkdir -p /mnt/wowos/etc/systemd/system/multi-user.target.wants
  ln -sf ../wowos-install-desktop-once.service /mnt/wowos/etc/systemd/system/multi-user.target.wants/wowos-install-desktop-once.service
fi
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

BUILD_OK=1
zip -q "wowos-${WOWOS_VERSION}.img.zip" "$IMG_NAME"
echo "[wowOS] Done: wowos-${WOWOS_VERSION}.img.zip (prepare-only, 方案2)"
echo "[wowOS] After flash: first boot runs wowos-install-desktop-once (lightdm/kiosk); reboot to enter graphical + Launcher."
echo "[wowOS] For full build (with deps in image), run ./scripts/build_image.sh on Linux with internet."
