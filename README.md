# wowdata — 树莓派语音助手

基于 [PRD](doc/voice_assistant_prd_v1_1.md) 与 [技术设计](doc/voice_assistant_technical_design_v1_1.md) 的语音助手底座项目。  
后端统一主控（状态机、音频链路、LLM、TTS），前端负责状态展示与配置；TTS 复用 **NAS 内网服务**（参见桌面 `AIGC/tts` 项目）。

## 技术栈

- **后端**：Python 3.10+，FastAPI，运行于树莓派本机 Docker
- **前端**：树莓派为 **纯原生桌面前端**（Python + PySide6，无 Web 嵌入）；另提供 React + Vite Web 前端（及可选 Electron 打包）供 Mac/浏览器使用
- **TTS**：调用 NAS 上的 TTS 服务（`http://<NAS的IP>:5002`，API 见 `AIGC/tts` 项目）
- **LLM**：DeepSeek API（可配置）

## 目录结构

```
wowdata/
├── apps/
│   ├── native/            # 树莓派纯原生前端（Python + Qt，无 Web）
│   ├── frontend/          # Web 前端（React，可选 Electron 打包）
│   └── backend/           # 后端核心
├── doc/                   # PRD、技术设计
├── docs/                  # API、日志等文档
├── scripts/               # 启动与部署脚本
├── samples/               # 示例配置与 mock 数据
└── README.md
```

## 快速开始

### 环境要求

- Mac（开发）/ Raspberry Pi OS Desktop（运行）
- Docker（树莓派上运行后端）
- Node.js 18+（前端开发）
- Python 3.10+（后端开发）

### 本地开发（Mac）

```bash
# 后端（需设置 PYTHONPATH）
cd apps/backend && pip install -r requirements.txt
export PYTHONPATH=src && uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
# 或直接：./scripts/run-backend-local.sh（在项目根目录）

# 前端（新终端）
cd apps/frontend && npm install && npm run dev
```
访问 http://localhost:5173 可看到「连接状态」页，后端需在 8000 端口运行。

### 树莓派首次部署

1. 将 Raspberry Pi OS Desktop 写入 TF 卡并启动
2. 连接 Wi-Fi（屏幕+键鼠）
3. 安装 Docker，拉取/构建后端镜像并启动
4. **前端（树莓派）**：在树莓派上运行 **纯原生应用**：`cd apps/native && pip3 install -r requirements.txt && python3 main.py`，或项目根目录 `./scripts/start-native.sh`（不嵌入任何 Web）

详见 [部署说明](docs/DEPLOY.md)。

## 配置说明

- **TTS**：在设置页配置 NAS TTS 地址（如 `http://192.168.2.128:5002`），与 `AIGC/tts` 项目部署的端口一致
- **LLM**：配置 DeepSeek API Key、模型、system prompt 等

## 相关项目

- **TTS 服务**：`桌面/AIGC/tts` — NAS 上部署的 Piper TTS，提供 `/health`、`/v1/tts`、`/v1/tts/stream` 等接口，wowdata 通过 HTTP 调用

## 功能概览（V1 已实现）

- **状态机与事件**：统一状态枚举、状态推送、WebSocket 实时状态/事件
- **配置中心**：GET/PUT 配置、前端设置页、本地 JSON 持久化
- **会话与日志**：session/turn 管理、按 turn 事件日志、日志查询 API、前端日志/单轮详情页
- **LLM**：DeepSeek 直连、流式回复、tool calling 闭环
- **工具**：注册表、执行器、内置 mock_get_time
- **TTS**：NAS TTS Provider（流式/同步 fallback）、对接桌面 AIGC/tts 项目
- **对话管道**：模拟输入 → ASR final → LLM（含 tool loop）→ TTS → 播放状态
- **调试**：POST 模拟输入、触发 mock tool、重置会话
- **前端**：首页（状态 + 模拟输入 + 重置）、设置、日志列表/详情、调试、系统

使用前请在**设置**中配置 **DeepSeek API Key** 和 **TTS 服务地址**（NAS 上部署的 tts 项目）。未配置 API Key 时 LLM 会报错；TTS 不可达时健康检查显示 tts 为 down，管道会尝试 fallback。
