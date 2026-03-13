# wowOS Kiosk 联调与排障

## 查看桌面安装服务

```bash
sudo systemctl status wowos-install-desktop-once.service --no-pager
sudo journalctl -u wowos-install-desktop-once.service -b --no-pager -n 100
```

## 查看 Web 服务

```bash
sudo systemctl status wowos-desktop.service --no-pager
sudo journalctl -u wowos-desktop.service -b --no-pager -n 100
```

## 查看 Kiosk 服务

```bash
sudo systemctl status wowos-kiosk.service --no-pager
sudo journalctl -u wowos-kiosk.service -b --no-pager -n 100
```

## 查看图形环境

```bash
systemctl get-default
systemctl status lightdm --no-pager
echo $DISPLAY
```
