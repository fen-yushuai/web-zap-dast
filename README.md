# DAST Pipeline

基于 Nuclei + OWASP ZAP 的动态应用安全测试平台。

## 前置条件

- Docker 已安装并运行
- 网络可访问 Docker Hub

## 快速开始

```bash
# 1. 安装依赖（拉取 Docker 镜像、下载 Nuclei 模板）
./scripts/setup.sh

# 2. 配置目标 URL
#    编辑 config.sh，设置 TARGET_URL

# 3. 运行扫描
./dast.sh
```

## 命令说明

### `dast.sh` — 主入口

```bash
./dast.sh                    # 完整流程（Nuclei + ZAP）
./dast.sh --setup            # 仅安装依赖
./dast.sh --scan nuclei      # 仅运行 Nuclei（快，2-5 分钟）
./dast.sh --scan zap         # 仅运行 ZAP（视目标复杂度）
./dast.sh --report-only DIR  # 从已有扫描数据重新生成报告
```

### `scripts/setup.sh` — 依赖安装

```bash
./scripts/setup.sh                 # 安装依赖并更新 Nuclei 模板
./scripts/setup.sh --skip-update   # 跳过模板更新（更快）
```

安装内容：
- `projectdiscovery/nuclei:latest` — Nuclei 扫描器，基于模板匹配已知漏洞、配置问题、信息泄露
- `zaproxy/zap-stable` — OWASP ZAP 扫描器，爬取 + 主动扫描，检测 XSS、SQL 注入、CSRF 等
- Nuclei 社区模板（~13000+ 条规则）

### `scripts/scan-nuclei.sh` — Nuclei 扫描

```bash
./scripts/scan-nuclei.sh                          # 默认配置扫描
./scripts/scan-nuclei.sh --severity critical,high  # 只扫高危
./scripts/scan-nuclei.sh --tags sqli,xss           # 指定模板标签
./scripts/scan-nuclei.sh --rate-limit 50           # 降低请求速率
```

输出格式：JSONL + SARIF

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

## 扫描类型说明

| 工具 | 扫描方式 | 适用场景 | 耗时 |
|------|----------|----------|------|
| Nuclei | 模板匹配 | 已知漏洞、配置问题、信息泄露 | 2-5 分钟 |
| ZAP full | 爬虫 + 主动扫描 | UI + API 全面覆盖 | 10-60+ 分钟 |
| ZAP API | 读 OpenAPI 文档 | 纯 API 接口 | 30 秒-5 分钟 |

### 选择建议

- **有 OpenAPI 文档** → ZAP API scan
- **前后端分离 SPA** → ZAP full scan（或 Nuclei 补充）
- **传统后端渲染网站** → ZAP full scan
- **快速检查已知漏洞** → Nuclei
- **全面覆盖** → Nuclei + ZAP full scan

## 常见场景

### 场景 1：扫描有 OpenAPI 文档的 API

```bash
# 修改 config.sh
TARGET_URL="https://api.example.com"
ZAP_API_DOCS_URL="https://api.example.com/v2/swagger.json"

# 运行（自动切换为 API scan）
./dast.sh --scan zap
```

### 场景 2：扫描传统网站（有 UI 页面）

```bash
# 修改 config.sh
TARGET_URL="https://your-website.com"

# 运行（full scan 会爬取页面，耗时较长）
./scripts/scan-zap.sh --scan-type full --timeout 30m
```

注意：full scan 在 Docker 内有 DomXSS 浏览器兼容问题，如果卡住可缩短超时：
```bash
./scripts/scan-zap.sh --scan-type full --timeout 10m
```

### 场景 3：扫描 SPA（单页应用）

SPA 页面靠 JS 渲染，传统爬虫爬不到。用 Nuclei + ZAP full scan 组合：

```bash
# 修改 config.sh
TARGET_URL="https://your-spa.com"

# Nuclei 扫描（模板匹配，不依赖爬虫）
./scripts/scan-nuclei.sh

# ZAP full scan（内部有 Ajax Spider 可爬 SPA）
./scripts/scan-zap.sh --scan-type full --timeout 20m
```

### 场景 4：只扫高危漏洞（快速）

```bash
# config.sh
NUCLEI_SEVERITY="critical,high"

# 或运行时传参
./scripts/scan-nuclei.sh --severity critical,high
```

### 场景 5：指定 Nuclei 模板标签

```bash
./scripts/scan-nuclei.sh --tags sqli           # SQL 注入
./scripts/scan-nuclei.sh --tags xss            # XSS
./scripts/scan-nuclei.sh --tags "sqli,xss,rce" # 多个标签

# 常用标签：sqli, xss, rce, ssrf, lfi, csti, default-login, exposure
```

### 场景 6：降低扫描速率（避免被封）

```bash
# config.sh
NUCLEI_RATE_LIMIT=20    # 从 100 降到 20 请求/秒
NUCLEI_CONCURRENCY=5    # 从 25 降到 5 并发

# 或运行时传参
./scripts/scan-nuclei.sh --rate-limit 20
```

### 场景 7：更新 Nuclei 模板

```bash
./scripts/setup.sh              # 更新模板 + 拉取镜像
./scripts/setup.sh --skip-update  # 跳过模板更新
```

手动更新：
```bash
docker run --rm -v ~/nuclei-templates:/root/nuclei-templates \
  projectdiscovery/nuclei:latest -update-templates
```

## 报告

扫描完成后，报告保存在 `reports/<timestamp>/` 目录：

```
reports/20260610_160214/
├── nuclei-results.json      # Nuclei 发现（JSONL）
├── nuclei-results.sarif     # Nuclei 发现（SARIF，可导入 IDE/GitHub）
├── nuclei-summary.txt       # Nuclei 按 severity 汇总
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
NUCLEI_URL_LIST=""                     # Nuclei URL 列表文件路径（可选）

# Nuclei
NUCLEI_SEVERITY="critical,high,medium,low"  # 扫描级别
NUCLEI_RATE_LIMIT=100                        # 请求/秒
NUCLEI_CONCURRENCY=25                        # 并发模板数

# ZAP
ZAP_MIN_ALERT_LEVEL="WARN"   # 最低告警级别
ZAP_TIMEOUT="300m"            # 最大扫描时长
ZAP_API_DOCS_URL=""           # API 文档完整地址，设置后自动切换为 API scan

# 平台
DOCKER_PLATFORM="linux/amd64"  # 默认 amd64，Apple Silicon 可改为 linux/arm64
```

## 常见问题

### Nuclei 报 "no templates provided"

模板未下载，运行：
```bash
docker run --rm -v ~/nuclei-templates:/root/nuclei-templates \
  projectdiscovery/nuclei:latest -update-templates
```

### ZAP 报 "Level must be one of [...]"

`-l` 参数值应为 `PASS|IGNORE|INFO|WARN|FAIL`，不是 `Low|Medium|High`。

### ZAP full scan 超时或卡住

DomXSS 规则在 Docker 内跑 Firefox 有兼容性问题。建议：
- 改用 `--scan-type api`（需 OpenAPI 文档）
- 或缩短超时 `--timeout 10m`

### ghcr.io 拉取超时

ZAP 镜像在 GitHub Container Registry，部分地区访问慢。可换成 Docker Hub 版本：
```bash
# 修改 config.sh
ZAP_IMAGE="zaproxy/zap-stable:latest"
```

### Apple Silicon 如何切换 arm64

修改 `config.sh`：
```bash
DOCKER_PLATFORM="linux/arm64"
```

可能的问题：
- 部分镜像没有 arm64 版本，会自动走 Rosetta 模拟（性能下降）
- ZAP 的 DomXSS 规则在 arm64 上兼容性差，已默认禁用
- 如果拉取镜像报错，改回 `linux/amd64`

### Nuclei exit code 1

Nuclei 找到漏洞时返回 1，这是正常行为（0 = 无发现，1 = 有发现，2+ = 错误）。
