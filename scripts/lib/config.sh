#!/usr/bin/env bash
# Central configuration for DAST pipeline

# --- Platform ---
# 默认 linux/amd64，Apple Silicon 用户可改为 linux/arm64（原生性能更好）
# 注意：部分镜像（如 ZAP）可能没有 arm64 版本，切换后可能需要走 Rosetta 模拟
DOCKER_PLATFORM="linux/arm64"

# --- Target ---
# 扫描目标 URL，如 TARGET_URL="https://example.com"
# Docker 容器内访问宿主机需用 host.docker.internal 代替 localhost
TARGET_URL="http://host.docker.internal:3000"

# --- Paths ---
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPORTS_DIR="${PROJECT_ROOT}/reports"

# --- ZAP ---
ZAP_IMAGE="zaproxy/zap-stable"
ZAP_CONTAINER="zap-dast"
ZAP_MIN_ALERT_LEVEL="WARN"
ZAP_TIMEOUT="300m"
# ZAP API 文档完整地址（如 https://api.example.com/api-docs），设置后自动切换为 API scan
ZAP_API_DOCS_URL=""

# --- Authentication ---
# 认证方式：form / form-csrf / api / http-basic / none
# 设为 none 或留空则不启用认证
ZAP_AUTH_TYPE="none"

# === Form-based Authentication（表单登录）===
ZAP_AUTH_LOGIN_URL=""
ZAP_AUTH_USERNAME_FIELD="username"
ZAP_AUTH_PASSWORD_FIELD="password"
ZAP_AUTH_USERNAME=""
ZAP_AUTH_PASSWORD=""
ZAP_AUTH_LOGGED_IN_INDICATOR=""
ZAP_AUTH_LOGGED_OUT_INDICATOR=""
ZAP_AUTH_CSRF_FIELD="user_token"   # CSRF hidden input 的 name 属性

# === API Authentication（API 接口登录）===
ZAP_AUTH_API_URL=""
ZAP_AUTH_API_BODY=""
ZAP_AUTH_API_TOKEN_PATH=""
ZAP_AUTH_API_TOKEN_LOCATION="header"
ZAP_AUTH_API_TOKEN_HEADER="Authorization"
ZAP_AUTH_API_TOKEN_PREFIX="Bearer "

# === HTTP Basic Authentication ===
ZAP_AUTH_BASIC_USERNAME=""
ZAP_AUTH_BASIC_PASSWORD=""

# --- ZAP Spider ---
# 爬取最大时长（分钟）
ZAP_SPIDER_MAX_DURATION=5
# 最大爬取深度
ZAP_SPIDER_MAX_DEPTH=5
# 是否启用 Ajax Spider（SPA 页面需要设为 true）
ZAP_SPIDER_AJAX_ENABLED=true
# Ajax Spider 最大时长（分钟），仅在 ZAP_SPIDER_AJAX_ENABLED=true 时生效
ZAP_SPIDER_AJAX_MAX_DURATION=5
