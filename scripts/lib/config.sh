#!/usr/bin/env bash
# Central configuration for DAST pipeline

# --- Platform ---
# 默认 linux/amd64，Apple Silicon 用户可改为 linux/arm64（原生性能更好）
# 注意：部分镜像（如 ZAP）可能没有 arm64 版本，切换后可能需要走 Rosetta 模拟
DOCKER_PLATFORM="linux/amd64"

# --- Target ---
# 扫描目标 URL，如 TARGET_URL="https://example.com"
# Docker 容器内访问宿主机需用 host.docker.internal 代替 localhost
TARGET_URL="http://testphp.vulnweb.com"

# --- Paths ---
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPORTS_DIR="${PROJECT_ROOT}/reports"

# --- Nuclei ---
NUCLEI_IMAGE="projectdiscovery/nuclei:latest"
NUCLEI_CONTAINER="nuclei-dast"
NUCLEI_SEVERITY="critical,high,medium,low"
NUCLEI_RATE_LIMIT=100
NUCLEI_CONCURRENCY=25
NUCLEI_TIMEOUT=10
# URL 列表文件（每行一个 URL），设置后优先使用列表扫描
NUCLEI_URL_LIST=""

# --- ZAP ---
ZAP_IMAGE="zaproxy/zap-stable"
ZAP_CONTAINER="zap-dast"
ZAP_MIN_ALERT_LEVEL="WARN"
ZAP_TIMEOUT="300m"
# ZAP API 文档完整地址（如 https://api.example.com/api-docs），设置后自动切换为 API scan
ZAP_API_DOCS_URL=""
