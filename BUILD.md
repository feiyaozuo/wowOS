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

> **Important:** wowOS must be flashed to a **microSD card**. Do not flash to a USB drive unless you have specifically configured your Raspberry Pi to USB-boot.

> **SD card size:** Use a **microSD card of at least 8 GB** (16 GB or larger recommended). The image is compact after build and automatically expands to fill the card on first boot.

1. Unzip: `unzip wowos-1.0.img.zip`
2. Flash using **[Raspberry Pi Imager](https://www.raspberrypi.com/software/)** (recommended):
   - Open Raspberry Pi Imager
   - Click **"Choose OS"** → **"Use custom"** and select `wowos-1.0.img`
   - Click **"Choose Storage"** and select your **microSD card** (not a USB drive)
   - *(Optional)* Click the gear ⚙ icon (Advanced Options) to pre-configure hostname, SSH user/password
   - Click **"Write"**

   Alternatively, use `dd` on Linux/macOS:
   ```bash
   sudo dd if=wowos-1.0.img of=/dev/sdX bs=4M status=progress conv=fsync
   ```
   (Replace `sdX` with your SD card device, e.g. `/dev/sdb`. **Do not use a USB drive path. Using the wrong device path will permanently erase all data on that device.**)
3. Eject the SD card safely, insert it into the Raspberry Pi's **microSD slot**, and power on.

## Troubleshooting

### Raspberry Pi does not recognize the SD card / Pi won't boot from SD card at all

If other images work on the same Raspberry Pi and SD card but the wowOS image does not, the card is likely in good health — the problem is almost always an **incomplete download**, a **write error during flash**, or a **corrupted partition table** in the image.

**Steps to fix:**

1. **Re-download the image** — the most common cause is a truncated or corrupted download. Compare the downloaded `.zip` file size against the size shown on the [Releases page](https://github.com/WowData-labs/wowOS/releases/latest). Delete the old file and download again, then unzip and re-flash.

2. **Re-flash with Raspberry Pi Imager** — Imager performs a post-write verification step that `dd` does not. Use Imager and watch for any error during the *Verifying* stage. If verification fails, the image or the card has a problem.
   - Open Raspberry Pi Imager  
   - Choose OS → Use custom → select `wowos-1.0.img`  
   - Choose Storage → select your microSD card  
   - Click **Write** and wait for verification to complete without errors.

3. **Verify the unzipped image is not truncated** — after `unzip wowos-1.0.img.zip`, run:
   ```bash
   # Check partition table is readable
   fdisk -l wowos-1.0.img
   ```
   You should see two partitions listed (a small FAT32 boot partition and a larger ext4 root partition). If `fdisk` reports errors or shows no partitions, the image is corrupt — re-download.

4. **Try a different microSD card** — even large (128 GB+) cards can have bad sectors near the beginning of the card that affect the partition table or boot partition. Try a different card to rule this out.

5. **Ensure the SD card is fully inserted** — press the microSD card firmly into the Pi's slot until it clicks. A card seated only partway will not be detected.

---

### Pi shows "Trying boot mode USB-MSD" / red screen with partition errors on startup

This means your Raspberry Pi is trying to boot from a **USB device** instead of the microSD card.  
It is the most common issue when the EEPROM boot order is set to try USB before SD, or when no valid SD card is present.

**Steps to fix:**

1. **Verify the SD card is inserted correctly** — make sure the microSD card is fully seated in the Raspberry Pi's SD card slot (bottom of the board).

2. **Re-flash the SD card** — the SD card may not have been written correctly.  Use Raspberry Pi Imager and follow the [Flash to SD card](#flash-to-sd-card) steps above. Do **not** select a USB drive as the target storage.

3. **Remove all USB storage devices** — unplug any USB drives or USB hard disks from the Raspberry Pi before booting. A connected USB drive can confuse the boot process if the EEPROM tries USB before SD.

4. **Raspberry Pi 5 EEPROM boot order** — on some Raspberry Pi 5 units the default EEPROM boot order may attempt USB-MSD before SD. To reset the boot order:
   - On a working Pi (or using another SD card with standard Raspberry Pi OS), run:
     ```bash
     sudo raspi-config
     ```
     Navigate to **Advanced Options → Boot Order** and select **SD Card Boot** (or set `BOOT_ORDER=0xf41` to try SD first).
   - Alternatively, from the command line:
     ```bash
     sudo rpi-eeprom-config --edit
     ```
     Set `BOOT_ORDER=0xf41` (digits are tried right-to-left: `4` = SD card, `1` = USB-MSD, `f` = restart loop), save, and reboot.

5. **Raspberry Pi Imager – use "Raspberry Pi 5" as the device** — when using Raspberry Pi Imager, select **Raspberry Pi 5** as the device type so the correct firmware files are written to the boot partition.

---

## After flash

- **SSH**: Enabled in image (`boot/ssh`). New Raspberry Pi OS may require Imager "Advanced options" to set hostname, user and password for headless; set them when flashing if needed.
- **API**: wowOS API runs automatically after boot on port **8080**.
- Check: `http://<Pi-IP>:8080/api/v1/health`; get token: `POST http://<IP>:8080/api/v1/tokens` (see DEV.md). Admin token is required in production (set via `wowos-firstboot`).
- **Optional**: Run `sudo wowos-firstboot` to set device password (for key derivation); otherwise default derivation is used.

## Included in image (full build)

- Users:
  - `wowos` (API runs as this service user)
  - `admin` (desktop session user, used by LightDM autologin; member of `video` and `input` groups)
- Dirs `/opt/wowos` (core), `/var/lib/wowos`, `/data` (data and audit)
- All Python deps from `requirements.txt` preinstalled
- Desktop stack preinstalled: `lightdm`, `lightdm-gtk-greeter`, `xserver-xorg`, `xinit`, `openbox`, `xserver-xorg-input-libinput`, `xserver-xorg-video-fbdev`, `libgl1-mesa-dri`, `chromium`, `unclutter`, `curl`, `dbus-x11`, `x11-xserver-utils`, `fonts-wqy-microhei`, NetworkManager
- systemd services enabled on boot:
  - `wowos-api.service`
  - `wowos-desktop.service` (Flask desktop web server on port 9090)
  - `wowos-kiosk.service` (Chromium kiosk, waits for X display and desktop server)
  - `lightdm` with graphical target as default
- LightDM autologin for user `admin` into Openbox session
- Openbox autostart configures display power-management and cursor hiding
- SSH enabled (boot partition contains `ssh` file)
