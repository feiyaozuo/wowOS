# wowOS Image Build and Flash

**Repo**: [https://github.com/feiyaozuo/wowOS](https://github.com/feiyaozuo/wowOS)

## Push code to GitHub

From project root (skip `remote add` if you already have a remote):

```bash
cd /path/to/wowOS
git init
git add .
git commit -m "Initial commit: wowOS core, apps, build scripts"
git branch -M main
git remote add origin https://github.com/feiyaozuo/wowOS.git
git push -u origin main
```

After push, GitHub Actions builds the image on Linux; open **Actions**, pick the latest run, then download `wowos-image` (i.e. `wowos-1.0.img.zip`) from **Artifacts**.

## Requirements

- **Full build (Python deps preinstalled in image)**: Must run on Linux (needs `losetup`, `mount`, `chroot`, and network inside chroot). Not supported on macOS.
- **Prepare-only build (recommended on macOS / Docker without network)**: No chroot apt; only copies wowOS code and sets up user and systemd. After flash, run dependency install once on the Pi (see below). Can use Docker on macOS.

## Build

### Option 1: Full build (Linux, needs network)

```bash
cd /path/to/wowOS
sudo ./scripts/build_image.sh
```

### Option 2: Prepare-only + Docker (including macOS)

```bash
cd /path/to/wowOS
./scripts/build_image_docker_prepare_only.sh
```

- Output: `build/wowos-1.0.img.zip`
- After flash, on the Pi run once: `sudo /root/wowos-firstboot-install.sh` (installs Python deps and starts API)

- First run downloads Raspberry Pi OS Lite (arm64) base image to `$BUILD_DIR` (default `/tmp/wowos-build`)
- Override with env: `BUILD_DIR`, `IMG_NAME`, `WOWOS_VERSION`
- Result: `wowos-1.0.img.zip` (contains `.img`)

### Option 3: Build on GitHub

Push to `main` or `master`, or trigger "Build wowOS Image" from the repo **Actions** page. Download `wowos-image` from the run’s **Artifacts** when done.

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

## Included in image

- User `wowos` (API runs as this user)
- Dirs `/opt/wowos` (core), `/var/lib/wowos`, `/data` (data and audit)
- systemd service `wowos-api.service` (enabled on boot)
- SSH enabled (boot partition contains `ssh` file)
