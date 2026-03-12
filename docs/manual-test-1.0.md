# wowOS 1.0 手工联调说明（草案）

本文件用于验证 wowOS 1.0 的核心闭环是否真实跑通：File Center、Home Assistant 轻接入、LLM Validate 与 desktop_server 代理。

## 1. 启动顺序与环境

1. 启动 wowOS API（本地开发示例）：

```bash
export WOWOS_API_PORT=8080
python3 -m wowos_core.api_server
```

2. 启动 App Center（如有）：

```bash
export WOWOS_APP_CENTER_PORT=8000
# 依据实际实现启动 app center 服务
```

3. 启动桌面服务器 / Launcher：

```bash
cd ui
export WOWOS_API_URL=http://127.0.0.1:8080
export WOWOS_APP_CENTER_URL=http://127.0.0.1:8000
export WOWOS_DESKTOP_PORT=9090
python3 desktop_server.py
```

浏览器访问 `http://127.0.0.1:9090/`，应看到 wowOS 首页。

## 2. Token 获取

1. 在生产模式下，通过 admin token 调用：

```bash
export WOWOS_ADMIN_TOKEN=...   # 与实例配置一致
curl -X POST http://127.0.0.1:8080/api/v1/tokens \
  -H "Authorization: Bearer $WOWOS_ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "app_id": "desktop",
    "user_id": "local-user",
    "resources": ["file/*"],
    "max_level": 3,
    "ttl": 86400
  }'
```

2. 将返回的 `token` 复制到桌面端 Settings 页（浏览器内 LocalStorage）。

## 3. File Center 联调

使用浏览器访问 `http://127.0.0.1:9090/file-center`。

### 3.1 基本链路

1. **上传文件**：选择任意文件，选择 Level，点击 Upload，上传成功且列表刷新。
2. **列表加载**：刷新页面，文件列表正常显示 name、level、tags、size、created_at。
3. **详情**：点击 Detail，弹窗显示 file_id、name、level、tags、category、size、created/updated。
4. **删除**：点击 Delete，确认后文件从列表中消失。

### 3.2 基本 curl 自测

```bash
# health
curl http://127.0.0.1:8080/api/v1/health

# list files
curl -H "Authorization: Bearer $TOKEN" \
  http://127.0.0.1:8080/api/v1/files

# file meta
curl -H "Authorization: Bearer $TOKEN" \
  http://127.0.0.1:8080/api/v1/files/$FILE_ID/meta
```

## 4. Home Assistant 联调

1. 在浏览器打开 `http://127.0.0.1:9090/home`。
2. 输入 Home Assistant URL（如 `http://homeassistant.local:8123`）与 Long-Lived Token。
3. 点击「Test connection」，状态显示 Connected。
4. 点击「Load entities」，显示实体列表。
5. 对灯或开关点击 On/Off 按钮，观察 HA 前端或实体状态变化，确认控制成功。

## 5. LLM Validate 联调

1. 在浏览器打开 `http://127.0.0.1:9090/llm`。
2. 确保环境变量中配置了：

```bash
export DEEPSEEK_API_KEY=...
export KIMI_API_KEY=...
```

3. 页面加载后 Provider 下拉能看到 DeepSeek/Kimi。
4. 选择一个 File Center 中已有的文件与 provider，保持「Redact first」勾选。
5. 点击「Send to LLM」，等待并看到返回内容；同时「Recent calls」列表出现新的记录。

## 6. desktop_server 代理校验

1. 所有 UI 静态资源（`/launcher/*`, `/file-center-ui/*`, `/home-ui/*`, `/llm-ui/*`）均能正常加载。
2. File Center 上传使用 `POST /api/proxy/files`，multipart 表单未丢失文件（后端能收到文件并存储）。
3. 所有经 `/api/proxy/...` 的请求都能正确携带 `Authorization: Bearer $TOKEN` 头。

