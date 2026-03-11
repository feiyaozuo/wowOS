# wowOS 镜像构建与烧录

**仓库**：[https://github.com/feiyaozuo/wowOS](https://github.com/feiyaozuo/wowOS)

## 上传代码到 GitHub

在项目根目录执行（首次或已有远程时跳过 `remote add`）：

```bash
cd /path/to/wowOS
git init
git add .
git commit -m "Initial commit: wowOS core, apps, build scripts"
git branch -M main
git remote add origin https://github.com/feiyaozuo/wowOS.git
git push -u origin main
```

推送后，GitHub Actions 会自动在 Linux 环境下构建镜像；在仓库页 **Actions** 中选中最近一次运行，完成后在 **Artifacts** 中下载 `wowos-image`（即 `wowos-1.0.img.zip`）。

## 环境要求

- **完整构建（镜像内预装 Python 依赖）**：必须在 Linux 本机执行（需要 `losetup`、`mount`、`chroot` 及 chroot 内可访问外网），macOS 不支持。
- **仅准备构建（推荐在 macOS / 无外网 Docker 下）**：不执行 chroot apt，只写入 wowOS 代码与用户、systemd；烧录后需在树莓派上执行一次依赖安装（见下）。可用 Docker 在 macOS 上完成。

## 构建步骤

### 方式一：完整构建（Linux 本机，需外网）

```bash
cd /path/to/wowOS
sudo ./scripts/build_image.sh
```

### 方式二：仅准备 + Docker（含 macOS）

```bash
cd /path/to/wowOS
./scripts/build_image_docker_prepare_only.sh
```

- 产物：`build/wowos-1.0.img.zip`
- 烧录后首次启动，在树莓派上执行一次：`sudo /root/wowos-firstboot-install.sh`（安装 Python 依赖并启动 API）

- 首次会下载 Raspberry Pi OS Lite (arm64) 基础镜像到 `$BUILD_DIR`（默认 `/tmp/wowos-build`）
- 可通过环境变量覆盖：`BUILD_DIR`、`IMG_NAME`、`WOWOS_VERSION`
- 完成后得到 `wowos-1.0.img.zip`（内含 `.img`）

### 方式三：在 GitHub 上自动构建

推送代码到 `main` 或 `master` 分支，或在该仓库 **Actions** 页手动触发 “Build wowOS Image”。构建完成后在对应 run 的 **Artifacts** 中下载 `wowos-image`。

## 烧录到 SD 卡

1. 解压：`unzip wowos-1.0.img.zip`
2. 使用 [Raspberry Pi Imager](https://www.raspberrypi.com/software/) 选择 “Use custom” 指向解压出的 `.img`，或使用 `dd`：
   ```bash
   sudo dd if=raspios-lite.img of=/dev/sdX bs=4M status=progress conv=fsync
   ```
   （将 `sdX` 替换为实际 SD 卡设备）
3. 插卡、上电启动树莓派

## 烧录后使用

- **SSH**：镜像内已启用（`boot/ssh`）。新版 Raspberry Pi OS 首次启动若无显示器会要求通过 Imager 的「高级选项」预置主机名、用户名与密码，建议烧录时在 Imager 中设置以便无头登录。
- **API**：系统启动后 wowOS API 服务自动运行，监听 **8080**。
- 访问：`http://<树莓派IP>:8080/api/v1/health` 检查；获取 Token：`POST http://<IP>:8080/api/v1/tokens`（见 DEV.md）。
- **可选**：登录后执行 `sudo wowos-firstboot` 设置设备密码（用于密钥派生），否则使用默认派生方式。

## 镜像内已包含

- 用户 `wowos`（API 服务运行身份）
- 目录 `/opt/wowos`（核心代码）、`/var/lib/wowos`、`/data`（数据与审计）
- systemd 服务 `wowos-api.service`（开机自启）
- SSH 已启用（boot 分区含 `ssh` 文件）
