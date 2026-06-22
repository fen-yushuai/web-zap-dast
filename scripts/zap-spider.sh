#!/usr/bin/env bash
# ZAP Spider - Website reconnaissance via crawling
# Usage: ./scripts/zap-spider.sh [--max-duration MIN] [--max-depth N] [--ajax] [--report-dir DIR]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/auth.sh"

ZAP_SPIDER_TARGET="${TARGET_URL}"
if [[ -z "$ZAP_SPIDER_TARGET" ]]; then
  log_error "TARGET_URL is empty, cannot run spider"
  exit 1
fi

# --- Parse arguments ---
MAX_DURATION="${ZAP_SPIDER_MAX_DURATION}"
MAX_DEPTH="${ZAP_SPIDER_MAX_DEPTH}"
AJAX_ENABLED="${ZAP_SPIDER_AJAX_ENABLED}"
AJAX_MAX_DURATION="${ZAP_SPIDER_AJAX_MAX_DURATION}"
REPORT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --max-duration)   MAX_DURATION="$2"; shift 2 ;;
    --max-depth)      MAX_DEPTH="$2"; shift 2 ;;
    --ajax)           AJAX_ENABLED=true; shift ;;
    --report-dir)     REPORT_DIR="$2"; shift 2 ;;
    *) log_error "Unknown option: $1"; exit 1 ;;
  esac
done

# --- Validate ---
if ! check_command docker; then
  log_error "Docker not found. Run: ./scripts/setup.sh"
  exit 1
fi

# --- Prepare reports ---
REPORT_DIR="${REPORT_DIR:-${REPORTS_DIR}/$(date +%Y%m%d_%H%M%S)}"
ensure_dir "${REPORT_DIR}"

URLS_FILE="${REPORT_DIR}/zap-spider-urls.txt"
SITEMAP_FILE="${REPORT_DIR}/zap-sitemap.txt"
SUMMARY_FILE="${REPORT_DIR}/zap-spider-summary.txt"

CONTAINER_NAME="zap-spider"
ZAP_API_BASE="http://localhost:8080"

log_info "=== ZAP Spider Reconnaissance ==="
log_info "Target:        ${ZAP_SPIDER_TARGET}"
log_info "Max duration:  ${MAX_DURATION} min"
log_info "Max depth:     ${MAX_DEPTH}"
log_info "Ajax spider:   ${AJAX_ENABLED}"
log_info "Reports:       ${REPORT_DIR}"

# --- Cleanup function ---
cleanup_zap() {
  log_info "Stopping ZAP container..."
  docker rm -f "${CONTAINER_NAME}" &>/dev/null || true
}
trap cleanup_zap EXIT

# --- Start ZAP in daemon mode ---
log_info "Starting ZAP daemon..."
docker run -d \
  --platform "${DOCKER_PLATFORM}" \
  --name "${CONTAINER_NAME}" \
  "${ZAP_IMAGE}" \
  zap.sh -daemon -port 8080 -config api.disablekey=true -config 'api.addrs.addr.name=.*' -config api.addrs.addr.regex=true \
  >/dev/null

# --- Set docker exec mode for zap_curl ---
ZAP_CONTAINER_EXEC="${CONTAINER_NAME}"

# --- Wait for ZAP API to be ready ---
log_info "Waiting for ZAP API to be ready..."
ZAP_READY=false
for i in $(seq 1 60); do
  if zap_curl "${ZAP_API_BASE}/JSON/core/view/version/" &>/dev/null; then
    ZAP_READY=true
    break
  fi
  sleep 2
done

if [[ "$ZAP_READY" != true ]]; then
  log_error "ZAP API did not start within 120 seconds"
  exit 1
fi

ZAP_VERSION=$(zap_curl "${ZAP_API_BASE}/JSON/core/view/version/" | jq -r '.version // "unknown"')
log_success "ZAP API ready (version: ${ZAP_VERSION})"

# --- Set up authentication if configured ---
setup_zap_auth "${ZAP_API_BASE}"

# --- Access target URL first (required by ZAP) ---
log_info "Accessing target URL to register with ZAP..."
ENCODED_URL=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${ZAP_SPIDER_TARGET}', safe=''))")
zap_curl "${ZAP_API_BASE}/JSON/core/action/accessUrl/?url=${ENCODED_URL}&followRedirects=true" >/dev/null

# --- Run traditional spider ---
log_info "Starting traditional spider (max: ${MAX_DURATION} min, depth: ${MAX_DEPTH})..."
# Use userId=0 (authenticated user) if auth is configured
SPIDER_USER_PARAM=""
if [[ "$ZAP_AUTH_TYPE" != "none" ]] && [[ -n "$ZAP_AUTH_TYPE" ]]; then
  SPIDER_USER_PARAM="&userId=0"
fi
SPIDER_ID=$(zap_curl "${ZAP_API_BASE}/JSON/spider/action/scan/?url=${ENCODED_URL}&maxChildren=${MAX_DEPTH}&recurse=true${SPIDER_USER_PARAM}" | jq -r '.scan // empty')

if [[ -z "$SPIDER_ID" ]]; then
  log_error "Failed to start traditional spider"
  exit 1
fi

# Poll spider progress
SPIDER_START=$(date +%s)
SPIDER_TIMEOUT=$((MAX_DURATION * 60))
while true; do
  SPIDER_STATUS=$(zap_curl "${ZAP_API_BASE}/JSON/spider/view/status/?scanId=${SPIDER_ID}" | jq -r '.status // "0"')
  log_info "Spider progress: ${SPIDER_STATUS}%"

  if [[ "$SPIDER_STATUS" -ge 100 ]] 2>/dev/null; then
    break
  fi

  ELAPSED=$(( $(date +%s) - SPIDER_START ))
  if [[ $ELAPSED -ge $SPIDER_TIMEOUT ]]; then
    log_warn "Spider timeout reached (${MAX_DURATION} min), stopping..."
    zap_curl "${ZAP_API_BASE}/JSON/spider/action/stop/?scanId=${SPIDER_ID}" >/dev/null
    break
  fi

  sleep 5
done

TRADITIONAL_URLS=$(zap_curl "${ZAP_API_BASE}/JSON/spider/view/results/?scanId=${SPIDER_ID}" | jq -r '.results[]?' 2>/dev/null | wc -l | tr -d ' ' || echo "0")
log_success "Traditional spider found ${TRADITIONAL_URLS} URLs"

# --- Run Ajax spider if enabled ---
AJAX_URLS=0
if [[ "$AJAX_ENABLED" == true ]]; then
  log_info "Starting Ajax spider (max: ${AJAX_MAX_DURATION} min)..."
  zap_curl "${ZAP_API_BASE}/JSON/ajaxSpider/action/scan/?url=${ENCODED_URL}" >/dev/null

  AJAX_START=$(date +%s)
  AJAX_TIMEOUT=$((AJAX_MAX_DURATION * 60))
  while true; do
    AJAX_STATUS=$(zap_curl "${ZAP_API_BASE}/JSON/ajaxSpider/view/status/" | jq -r '.status // "RUNNING"')
    log_info "Ajax spider status: ${AJAX_STATUS}"

    if [[ "$(echo "$AJAX_STATUS" | tr '[:upper:]' '[:lower:]')" == "stopped" ]]; then
      break
    fi

    ELAPSED=$(( $(date +%s) - AJAX_START ))
    if [[ $ELAPSED -ge $AJAX_TIMEOUT ]]; then
      log_warn "Ajax spider timeout reached (${AJAX_MAX_DURATION} min), stopping..."
      zap_curl "${ZAP_API_BASE}/JSON/ajaxSpider/action/stop/" >/dev/null
      break
    fi

    sleep 5
  done

  AJAX_URLS=$(zap_curl "${ZAP_API_BASE}/JSON/ajaxSpider/view/fullResults/" 2>/dev/null | jq -r '.fullResults[]?.url // empty' 2>/dev/null | wc -l | tr -d ' ' || true)
  AJAX_URLS="${AJAX_URLS:-0}"
  AJAX_URLS="${AJAX_URLS:-0}"
  log_success "Ajax spider found ${AJAX_URLS} URLs"
fi

# --- Export results ---
log_info "Exporting spider results..."

# All URLs (from both spiders)
zap_curl "${ZAP_API_BASE}/JSON/core/view/urls/" | jq -r '.urls[]?' 2>/dev/null | sort -u > "${URLS_FILE}" || true
TOTAL_URLS=$(wc -l < "${URLS_FILE}" | tr -d ' ' || echo "0")

# Site tree
zap_curl "${ZAP_API_BASE}/JSON/core/view/sitemap/" | jq -r '.siteList[]?' 2>/dev/null | sort -u > "${SITEMAP_FILE}" || true

# --- Generate summary ---
{
  echo "=== ZAP Spider Summary ==="
  echo "Target:           ${ZAP_SPIDER_TARGET}"
  echo "Date:             $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""
  echo "--- Results ---"
  echo "Traditional spider: ${TRADITIONAL_URLS} URLs"
  if [[ "$AJAX_ENABLED" == true ]]; then
    echo "Ajax spider:        ${AJAX_URLS} URLs"
  fi
  echo "All URLs in ZAP session: ${TOTAL_URLS} (includes auth, redirects, resources)"
  echo ""
  echo "--- Configuration ---"
  echo "Max depth:      ${MAX_DEPTH}"
  echo "Max duration:   ${MAX_DURATION} min"
  echo "Ajax spider:    ${AJAX_ENABLED}"
  echo ""
  echo "URL list:  zap-spider-urls.txt"
  echo "Sitemap:   zap-sitemap.txt"
} | tee "${SUMMARY_FILE}"

log_success "=== Spider reconnaissance complete ==="
log_success "Found ${TOTAL_URLS} URLs in ZAP session"
log_success "Summary: ${SUMMARY_FILE}"
