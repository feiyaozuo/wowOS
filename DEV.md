# wowOS 开发与运行说明

## 本地运行（无需树莓派）

### 1. 安装依赖

```bash
pip3 install -r requirements.txt
```

### 2. 启动系统 API

```bash
python3 run_api.py
# 默认 http://localhost:8080
```

### 3. 获取 Token 并测试

```bash
# 生成 Token
curl -X POST http://localhost:8080/api/v1/tokens \
  -H "Content-Type: application/json" \
  -d '{"app_id":"test","user_id":"u1","resources":["file/*"],"max_level":3,"ttl":3600}'

# 上传文件（将 TOKEN 替换为上一步返回的 token）
curl -X POST http://localhost:8080/api/v1/files \
  -H "Authorization: Bearer TOKEN" \
  -F "file=@/path/to/file" -F "privacy_level=3"

# 下载文件
curl -H "Authorization: Bearer TOKEN" "http://localhost:8080/api/v1/files/FILE_ID" -o out
```

### 4. 使用 mock_os 开发应用

```bash
# 终端 1：启动 mock 服务
python3 run_mock_os.py
# 默认 http://localhost:8081

# 终端 2：以 mock 模式运行家庭账本
export WOWOS_MOCK=1
cd apps/family-ledger && python3 app.py
# 访问 http://localhost:5001
```

### 5. 应用中心与打包

- 将应用打成 `.wapp`（tar.gz，内含 manifest.json 等）放入 `app_center/packages/`
- 生成索引：`cd app_center && python3 generate_index.py`
- 启动静态服务：`cd app_center && python3 -m http.server 8000`
- 应用管理：使用 `apps/app_manager.py` 的 `AppManager` 安装/卸载（需配置应用中心 URL）

### 6. 数据目录

- 开发环境默认使用项目下 `data/`（审计库、撤销列表、文件存储、应用 DB 等）
- 可通过环境变量覆盖：`VAR_LIB_WOWOS`、`WOWOS_DATA_PATH`、`WOWOS_AUDIT_DB` 等
