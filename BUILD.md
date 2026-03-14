# wowOS Image Build and Flash

**Repo**: [https://github.com/WowData-labs/wowOS](https://github.com/WowData-labs/wowOS)

## Push code to GitHub

From project root (skip `remote add` if you already have a remote):

```bash
cd /path/to/wowOS
git init
git add .
git commit -m "Initial commit: wowOS core, apps, build scripts"
git branch -M main
git remote add origin https://github.com/WowData-labs/wowOS.git
git push -u origin main
```

After push, GitHub Actions builds the image on Linux; the finished image is published as a **[GitHub Release](https://github.com/WowData-labs/wowOS/releases/latest)** — go to the **Releases** page and download `wowos-1.0.img.zip` directly.  
Alternatively, open **Actions**, pick the latest run, then download `wowos-image` from **Artifacts** (available for 7 days).

## Requirements

- **Full build (recommended, all deps baked into image)**: Runs on Linux (native or inside Docker) with `losetup`, `mount`, `kpartx`, `zip`, and network access inside chroot.
- **Prepare-only build (dev only, not for production)**: Legacy mode that does *not* install all deps into the image and expects extra steps on the Pi. Keep only for local experimentation.

## Build

### Option 1: Full build on Linux host (all deps preinstalled)

```bash
cd /path/to/wowOS
sudo ./scripts/build_image.sh
```

### Option 2: Full build via Docker (works well from macOS)

```bash
cd /path/to/wowOS
./scripts/build_image_docker.sh
```

- Output: `build/wowos-1.0.img.zip`
- First run downloads Raspberry Pi OS Lite (arm64) base image to `$BUILD_DIR` (default `build/`)
- Override with env: `BUILD_DIR`, `IMG_NAME`, `WOWOS_VERSION`
- Result: `wowos-1.0.img.zip` (contains `.img` with Python + desktop deps + wowOS services preinstalled)

### Option 3: Build on GitHub (full build inside privileged Docker)

Push to `main` or `master`, or trigger "Build wowOS Image" from the repo **Actions** page.  
Once the build succeeds, a **GitHub Release** is created automatically — download `wowos-1.0.img.zip` directly from the **[Releases page](https://github.com/WowData-labs/wowOS/releases/latest)**.  
The GitHub workflow runs `scripts/build_image.sh` inside a privileged Docker container, so the downloaded image already includes all required Python and desktop dependencies.

## Flash to SD card

1. Unzip: `unzip wowos-1.0.img.zip`
2. Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/) → "Use custom" and point to the extracted `.img`, or use `dd`:
   ```bash
   sudo dd if=raspios-lite.img of=/dev/sdX bs=4M status=progress conv=fsync
   ```
   (Replace `sdX` with your SD device.)
3. Insert card and power on the Pi.

## After flash

- **SSH**: Enabled in image (`boot/ssh`). New Raspberry Pi OS may require Imager "Advanced options" to set hostname, user and password for headless; set them when flashing if needed.
- **API**: wowOS API runs automatically after boot on port **8080**.
- Check: `http://<Pi-IP>:8080/api/v1/health`; get token: `POST http://<IP>:8080/api/v1/tokens` (see DEV.md). Admin token is required in production (set via `wowos-firstboot`).
- **Optional**: Run `sudo wowos-firstboot` to set device password (for key derivation); otherwise default derivation is used.

## Included in image (full build)

- Users:
  - `wowos` (API runs as this service user)
  - `admin` (desktop session user, used by LightDM autologin)
- Dirs `/opt/wowos` (core), `/var/lib/wowos`, `/data` (data and audit)
- All Python deps from `requirements.txt` preinstalled
- Desktop stack preinstalled: `lightdm`, `xserver-xorg`, `xinit`, `openbox`, `chromium`, `unclutter`, `dbus-x11`, `x11-xserver-utils`, fonts, NetworkManager
- systemd services enabled on boot:
  - `wowos-api.service`
  - `wowos-desktop.service`
  - `wowos-kiosk.service`
  - `lightdm` with graphical target as default
- LightDM autologin for user `admin` into Openbox session
- Openbox autostart launches wowOS kiosk (`start_kiosk.sh`)
- SSH enabled (boot partition contains `ssh` file)
