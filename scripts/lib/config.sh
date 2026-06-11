#!/usr/bin/env bash
# Central configuration for DAST pipeline

# --- Platform ---
# Explicit arm64 to override DOCKER_DEFAULT_PLATFORM=linux/amd64 if set
DOCKER_PLATFORM="linux/arm64"

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
