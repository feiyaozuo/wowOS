# 方案2 镜像构建链一致性说明

## 统一逻辑

以下四种出镜像方式均使用**同一套方案2 逻辑**（桌面标记 `.desktop_installed`，脚本在 `/opt/wowos/scripts/`，kiosk 在 graphical.target）：

| 构建方式 | 脚本 | 说明 |
|----------|------|------|
| 本地（Linux） | `scripts/build_image_prepare_only.sh` | 无 chroot apt，首启执行 install_desktop_once |
| 本地 Docker | `scripts/build_image_docker_prepare_only.sh` | 同上，在容器内执行 |
| 本地完整构建 | `scripts/build_image.sh` / `scripts/build_image_docker.sh` | 含 chroot 装依赖，同样复制 install_desktop_once + start_kiosk + wowos-kiosk.service |
| GitHub Actions | `.github/workflows/build-image.yml` → `build_image_prepare_only.sh` | 与本地 prepare-only 一致 |

## 有效构建链中不再出现

- `install_desktop_firstboot.sh`
- `/usr/local/bin/wowos-install-desktop-firstboot`
- `/root/wowos-firstboot-install.sh`
- 标记文件 `desktop-installed`（已改为 `.desktop_installed`）

## 有效构建链中应出现

- `install_desktop_once.sh` → `/opt/wowos/scripts/`
- `start_kiosk.sh` → `/opt/wowos/scripts/`
- `wowos-kiosk.service` → `graphical.target.wants`
- 标记文件：`/var/lib/wowos/.desktop_installed`

---

# 首次启动 / 第二次启动验收步骤

## 首次启动（烧录后第一次开机）

1. 树莓派上电，等待网络就绪。
2. 验证一次性安装服务：
   ```bash
   sudo systemctl status wowos-install-desktop-once.service --no-pager
   sudo journalctl -u wowos-install-desktop-once.service -b --no-pager -n 80
   ```
   - 应看到执行 `install_desktop_once.sh`（apt 装 lightdm/xorg/openbox/chromium/unclutter，set-default graphical.target，enable wowos-api/desktop/kiosk）。
3. 验证标记文件已创建：
   ```bash
   ls -la /var/lib/wowos/.desktop_installed
   ```
   - 应存在。
4. 验证默认 target：
   ```bash
   systemctl get-default
   ```
   - 应为 `graphical.target`。
5. **重启**：`sudo reboot`

## 第二次启动（首次启动完成并重启后）

1. 开机后应**自动进入图形桌面**（不再停留在 tty1 登录界面）。
2. 应**自动启动 Chromium kiosk**，全屏打开 `http://127.0.0.1:9090`，显示 wowOS Launcher。
3. 验证服务：
   ```bash
   systemctl get-default                    # graphical.target
   systemctl is-active wowos-api             # active
   systemctl is-active wowos-desktop         # active
   systemctl is-active wowos-kiosk           # active
   ```
4. 一次性安装服务不应再执行：
   ```bash
   sudo systemctl status wowos-install-desktop-once.service --no-pager
   ```
   - 可能为 inactive/disabled 或 ConditionPathExists 未满足（因 `.desktop_installed` 已存在）。

## P0 验收（文档 十）

- 树莓派开机后不再停留在 tty1 登录界面。
- 系统进入图形桌面。
- HDMI 屏幕自动打开 Chromium。
- 浏览器自动显示 wowOS Launcher。
