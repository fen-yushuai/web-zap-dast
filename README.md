# DAST Pipeline

基于 OWASP ZAP 的动态应用安全测试平台，支持 Spider 爬取 + 主动扫描。

## 前置条件

- Docker 已安装并运行
- 网络可访问 Docker Hub
- 支持系统：macOS（Intel / Apple Silicon）、Linux（amd64 / arm64），Windows 需 WSL2
- 已验证：macOS Apple Silicon（arm64）

## 快速开始

```bash
# 1. 安装依赖（拉取 Docker 镜像）
./scripts/setup.sh

# 2. 配置扫描目标
#    编辑 config.sh，参照下方「常见场景」配置

# 3. 运行扫描
./dast.sh
```

## 常见场景

### 场景 1：扫描有 OpenAPI 文档的 API ✅ 已验证

```bash
# 修改 config.sh
TARGET_URL="https://api.example.com"
ZAP_API_DOCS_URL="https://api.example.com/v2/swagger.json"

# 运行（自动切换为 API scan，跳过 spider）
./dast.sh --scan zap
```
> 已测试靶场：OWASP Juice Shop（Swagger JSON），31 个 URL，22 秒完成

### 场景 2：扫描传统网站

```bash
# 修改 config.sh
TARGET_URL="https://your-website.com"

# 完整流程：spider 爬取 + ZAP 扫描
./dast.sh
```

### 场景 3：扫描 SPA（单页应用）✅ 已验证

SPA 页面靠 JS 渲染，传统爬虫爬不到，需要 Ajax Spider：

```bash
# 修改 config.sh
TARGET_URL="https://your-spa.com"
ZAP_SPIDER_AJAX_ENABLED=true

# 运行
./dast.sh
```

或命令行：
```bash
./scripts/zap-spider.sh --ajax --max-duration 10
```
> 已测试靶场：OWASP Juice Shop（Angular SPA），传统 19 URL + Ajax 发现共 75 URL

### 场景 4：需要登录的网站

修改 `config.sh`，根据登录方式配置认证信息：

**API Token 登录** ✅ 已验证（靶场：OWASP Juice Shop）：
```bash
# 启动靶场
docker run -d --name juice-shop -p 3000:3000 bkimminich/juice-shop

# config.sh
TARGET_URL="http://host.docker.internal:3000"
ZAP_AUTH_TYPE="api"
ZAP_AUTH_API_URL="http://host.docker.internal:3000/rest/user/login"
ZAP_AUTH_API_BODY='{"email":"__USERNAME__","password":"__PASSWORD__"}'
ZAP_AUTH_USERNAME="admin@juice-sh.op"
ZAP_AUTH_PASSWORD="admin123"
ZAP_AUTH_API_TOKEN_PATH="authentication.token"
ZAP_AUTH_API_TOKEN_LOCATION="header"
ZAP_AUTH_API_TOKEN_HEADER="Authorization"
ZAP_AUTH_API_TOKEN_PREFIX="Bearer "
```

**简单表单登录** ✅ 已验证（靶场：自建 PHP 应用）：
```bash
# 适用于无 CSRF token 保护的简单登录页，需自行搭建测试应用
# config.sh
TARGET_URL="http://host.docker.internal:8080"
ZAP_AUTH_TYPE="form"
ZAP_AUTH_LOGIN_URL="http://host.docker.internal:8080/login"
ZAP_AUTH_USERNAME_FIELD="login"         # 表单中用户名字段的 name
ZAP_AUTH_PASSWORD_FIELD="password"      # 表单中密码字段的 name
ZAP_AUTH_USERNAME="admin"
ZAP_AUTH_PASSWORD="admin"
ZAP_AUTH_LOGGED_IN_INDICATOR="Welcome"  # 登录成功后页面包含的文字
ZAP_AUTH_LOGGED_OUT_INDICATOR="Login"   # 登录失败后页面包含的文字
```

**带 CSRF 的表单登录** ✅ 已验证（靶场：DVWA）：
```bash
# 启动靶场（Apple Silicon 需加 --platform linux/amd64）
docker run -d --name dvwa -p 8080:80 vulnerables/web-dvwa

# 浏览器访问 http://localhost:8080，点击 Create / Reset Database 初始化
# 默认凭据：admin / password

# config.sh
TARGET_URL="http://host.docker.internal:8080"
ZAP_AUTH_TYPE="form-csrf"
ZAP_AUTH_LOGIN_URL="http://host.docker.internal:8080/login.php"
ZAP_AUTH_USERNAME_FIELD="username"
ZAP_AUTH_PASSWORD_FIELD="password"
ZAP_AUTH_CSRF_FIELD="user_token"       # CSRF hidden input 的 name
ZAP_AUTH_USERNAME="admin"
ZAP_AUTH_PASSWORD="password"
ZAP_AUTH_LOGGED_IN_INDICATOR="You have logged in"
ZAP_AUTH_LOGGED_OUT_INDICATOR="Login"
```
> 使用 ZAP scriptBasedAuthentication，自动 GET 登录页提取 CSRF token 后 POST 登录
> 如目标站点的 CSRF token 提取逻辑不同（如 meta tag、cookie 等），需修改 `scripts/zap/auth-csrf.js` 中的正则

**HTTP Basic 登录** ✅ 已验证（靶场：httpbin）：
```bash
# 启动靶场
docker run -d --name httpbin -p 8080:80 kennethreitz/httpbin

# config.sh
TARGET_URL="http://host.docker.internal:8080"
ZAP_AUTH_TYPE="http-basic"
ZAP_AUTH_BASIC_USERNAME="admin"
ZAP_AUTH_BASIC_PASSWORD="admin123"
```
> 测试端点：`/basic-auth/admin/admin123`

### 场景 5：只看爬取结果（不做扫描）

```bash
./dast.sh --scan spider
# 查看发现的 URL
cat reports/<timestamp>/zap-spider-urls.txt
```

### 场景 6：降低扫描速率（避免被封）

```bash
# config.sh
ZAP_SPIDER_MAX_DURATION=2    # 缩短爬取时间
ZAP_SPIDER_MAX_DEPTH=2       # 减少爬取深度

# 或运行时传参
./scripts/zap-spider.sh --max-duration 2 --max-depth 2
```

## 命令说明

### `dast.sh` — 主入口

```bash
./dast.sh                    # 完整流程（Spider 爬取 + ZAP 扫描）
./dast.sh --setup            # 仅安装依赖
./dast.sh --scan spider      # 仅运行 Spider 爬取（网站认知）
./dast.sh --scan zap         # 仅运行 ZAP 扫描
./dast.sh --report-only DIR  # 从已有扫描数据重新生成报告
```

### `scripts/zap-spider.sh` — Spider 爬取

先爬取目标网站，发现所有可访问的 URL，再交给 ZAP 扫描。

```bash
./scripts/zap-spider.sh                        # 默认配置爬取
./scripts/zap-spider.sh --max-duration 10      # 爬取 10 分钟
./scripts/zap-spider.sh --max-depth 10         # 最大深度 10 层
./scripts/zap-spider.sh --ajax                 # 启用 Ajax Spider（SPA 需要）
```

输出：
- `zap-spider-urls.txt` — 发现的所有 URL（每行一个）
- `zap-sitemap.txt` — 站点树结构
- `zap-spider-summary.txt` — 爬取统计摘要

### `scripts/scan-zap.sh` — ZAP 扫描

```bash
./scripts/scan-zap.sh                    # full scan（爬取 + 主动扫描）
./scripts/scan-zap.sh --scan-type api    # API scan（需 OpenAPI 文档）
./scripts/scan-zap.sh --min-alert INFO   # 包含 INFO 级别
./scripts/scan-zap.sh --timeout 60m      # 限制扫描时间
```

扫描类型：
- **full** — 传统爬虫 + 主动扫描，覆盖 UI 和 API，耗时长
- **api** — 直接读 OpenAPI/Swagger 文档，快速精准，30 秒左右

## 扫描流程

```
Target URL
    │
    ▼
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Spider    │────▶│  ZAP Scan   │────▶│   Report    │
│  爬取发现   │     │  主动扫描   │     │  汇总报告   │
└─────────────┘     └─────────────┘     └─────────────┘
```

1. **Spider 阶段**：爬取目标网站，发现所有可访问的 URL 和站点结构
2. **Scan 阶段**：对发现的 URL 进行主动安全扫描（XSS、SQL 注入、CSRF 等）
3. **Report 阶段**：汇总扫描结果，生成 HTML/JSON/XML 报告

## 报告

扫描完成后，报告保存在 `reports/<timestamp>/` 目录：

```
reports/20260610_160214/
├── zap-spider-urls.txt      # Spider 发现的 URL 列表
├── zap-sitemap.txt          # 站点树结构
├── zap-spider-summary.txt   # Spider 爬取统计
├── zap-report.html          # ZAP 报告（HTML，浏览器打开）
├── zap-report.json          # ZAP 发现（JSON）
├── zap-report.xml           # ZAP 发现（XML）
├── zap-summary.txt          # ZAP 按 risk level 汇总
└── summary.md               # 合并汇总报告
```

## 配置

所有可配置项在 `scripts/lib/config.sh`：

```bash
# 扫描目标
TARGET_URL=""                          # 扫描目标 URL（必填）

# ZAP
ZAP_MIN_ALERT_LEVEL="WARN"   # 最低告警级别
ZAP_TIMEOUT="300m"            # 最大扫描时长
ZAP_API_DOCS_URL=""           # API 文档完整地址，设置后自动切换为 API scan

# ZAP Spider
ZAP_SPIDER_MAX_DURATION=5    # 爬取最大时长（分钟）
ZAP_SPIDER_MAX_DEPTH=5       # 最大爬取深度
ZAP_SPIDER_AJAX_ENABLED=false # 是否启用 Ajax Spider（SPA 页面需要）
ZAP_SPIDER_AJAX_MAX_DURATION=5 # Ajax Spider 最大时长（分钟）

# 认证（详见"场景 6"）
ZAP_AUTH_TYPE="none"          # form / form-csrf / api / http-basic / none
# 表单登录相关
ZAP_AUTH_LOGIN_URL=""
ZAP_AUTH_USERNAME=""
ZAP_AUTH_PASSWORD=""
ZAP_AUTH_CSRF_FIELD="user_token"  # CSRF hidden input 的 name（form-csrf 用）
# API 登录相关
ZAP_AUTH_API_URL=""
ZAP_AUTH_API_BODY=""
ZAP_AUTH_API_TOKEN_PATH=""
# HTTP Basic 相关
ZAP_AUTH_BASIC_USERNAME=""
ZAP_AUTH_BASIC_PASSWORD=""

# 平台
DOCKER_PLATFORM="linux/amd64"  # 默认 amd64，Apple Silicon 可改为 linux/arm64
```

## 常见问题

### ZAP 报 "Level must be one of [...]"

`-l` 参数值应为 `PASS|IGNORE|INFO|WARN|FAIL`，不是 `Low|Medium|High`。

### ZAP full scan 超时或卡住

DomXSS 规则在 Docker 内跑 Firefox 有兼容性问题。建议：
- 改用 `--scan-type api`（需 OpenAPI 文档）
- 或缩短超时 `--timeout 10m`

### Spider 爬不到页面

- SPA 页面需要启用 Ajax Spider：`ZAP_SPIDER_AJAX_ENABLED=true`
- 增加爬取深度：`ZAP_SPIDER_MAX_DEPTH=10`
- 增加爬取时间：`ZAP_SPIDER_MAX_DURATION=15`

### Apple Silicon 如何切换 arm64

修改 `config.sh`：
```bash
DOCKER_PLATFORM="linux/arm64"
```

可能的问题：
- 部分镜像没有 arm64 版本，会自动走 Rosetta 模拟（性能下降）
- ZAP 的 DomXSS 规则在 arm64 上兼容性差，已默认禁用
- 如果拉取镜像报错，改回 `linux/amd64`
