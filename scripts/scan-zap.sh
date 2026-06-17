#!/usr/bin/env bash
# OWASP ZAP scan wrapper
# Usage: ./scripts/scan-zap.sh [--scan-type full|api] [--timeout DURATION] [--min-alert LEVEL]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/auth.sh"

ZAP_TARGET="${TARGET_URL}"
if [[ -z "$ZAP_TARGET" ]]; then
  log_error "TARGET_URL is empty, cannot run ZAP scan"
  exit 1
fi

# --- Parse arguments ---
# 自动判断：设置了 ZAP_API_DOCS_URL 则用 api scan，否则用 full scan
if [[ -n "$ZAP_API_DOCS_URL" ]]; then
  SCAN_TYPE="api"
else
  SCAN_TYPE="full"
fi
TIMEOUT="${ZAP_TIMEOUT}"
MIN_ALERT="${ZAP_MIN_ALERT_LEVEL}"
REPORT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scan-type)  SCAN_TYPE="$2"; shift 2 ;;
    --timeout)    TIMEOUT="$2"; shift 2 ;;
    --min-alert)  MIN_ALERT="$2"; shift 2 ;;
    --report-dir) REPORT_DIR="$2"; shift 2 ;;
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

REPORT_HTML="${REPORT_DIR}/zap-report.html"
REPORT_JSON="${REPORT_DIR}/zap-report.json"
REPORT_XML="${REPORT_DIR}/zap-report.xml"
REPORT_LOG="${REPORT_DIR}/zap-output.log"
REPORT_SUMMARY="${REPORT_DIR}/zap-summary.txt"


AUTH_ENABLED=false
if [[ "$ZAP_AUTH_TYPE" != "none" ]] && [[ -n "$ZAP_AUTH_TYPE" ]]; then
  AUTH_ENABLED=true
fi

# --- Authenticated scan via daemon mode ---
ZAP_SCAN_CONTAINER="zap-scan-daemon"

run_auth_scan() {
  local scan_api_url="http://localhost:8080"

  log_info "Starting ZAP daemon for authenticated scan..."

  # Cleanup function
  cleanup_zap_scan() {
    log_info "Stopping ZAP scan container..."
    docker rm -f "${ZAP_SCAN_CONTAINER}" &>/dev/null || true
  }
  trap cleanup_zap_scan EXIT

  docker run -d \
    --platform "${DOCKER_PLATFORM}" \
    --name "${ZAP_SCAN_CONTAINER}" \
    "${ZAP_IMAGE}" \
    zap.sh -daemon -port 8080 -config api.disablekey=true -config 'api.addrs.addr.name=.*' -config api.addrs.addr.regex=true \
    >/dev/null

  # Set docker exec mode for zap_curl
  ZAP_CONTAINER_EXEC="${ZAP_SCAN_CONTAINER}"

  # Wait for API
  log_info "Waiting for ZAP API..."
  local ready=false
  for i in $(seq 1 60); do
    if zap_curl "${scan_api_url}/JSON/core/view/version/" &>/dev/null; then
      ready=true
      break
    fi
    sleep 2
  done

  if [[ "$ready" != true ]]; then
    log_error "ZAP API did not start within 120 seconds"
    exit 1
  fi

  local zap_ver
  zap_ver=$(zap_curl "${scan_api_url}/JSON/core/view/version/" | jq -r '.version // "unknown"')
  log_success "ZAP API ready (version: ${zap_ver})"

  # Set up authentication
  setup_zap_auth "${scan_api_url}"

  # Access target
  local encoded_target
  encoded_target=$(urlencode "${ZAP_TARGET}")
  zap_curl "${scan_api_url}/JSON/core/action/accessUrl/?url=${encoded_target}&followRedirects=true" >/dev/null

  # Run spider
  local timeout_seconds
  timeout_seconds=$(parse_timeout "${TIMEOUT}")
  local spider_duration=$((timeout_seconds / 3 > 300 ? 300 : timeout_seconds / 3))

  log_info "Running spider (max: ${spider_duration}s)..."
  local spider_id
  spider_id=$(zap_curl "${scan_api_url}/JSON/spider/action/scan/?url=${encoded_target}&maxChildren=5&recurse=true&userId=0" | jq -r '.scan // empty')

  if [[ -n "$spider_id" ]]; then
    local spider_start spider_elapsed
    spider_start=$(date +%s)
    while true; do
      local status
      status=$(zap_curl "${scan_api_url}/JSON/spider/view/status/?scanId=${spider_id}" | jq -r '.status // "0"')
      if [[ "$status" -ge 100 ]] 2>/dev/null; then
        break
      fi
      spider_elapsed=$(( $(date +%s) - spider_start ))
      if [[ $spider_elapsed -ge $spider_duration ]]; then
        log_warn "Spider timeout, stopping..."
        zap_curl "${scan_api_url}/JSON/spider/action/stop/?scanId=${spider_id}" >/dev/null
        break
      fi
      sleep 5
    done
    log_success "Spider complete"
  fi

  # Run active scanner
  log_info "Running active scanner..."
  local scan_id
  scan_id=$(zap_curl "${scan_api_url}/JSON/ascan/action/scan/?url=${encoded_target}&recurse=true" | jq -r '.scan // empty')

  if [[ -n "$scan_id" ]]; then
    local scan_start scan_elapsed
    scan_start=$(date +%s)
    while true; do
      local status
      status=$(zap_curl "${scan_api_url}/JSON/ascan/view/status/?scanId=${scan_id}" | jq -r '.status // "0"')
      log_info "Scan progress: ${status}%"
      if [[ "$status" -ge 100 ]] 2>/dev/null; then
        break
      fi
      scan_elapsed=$(( $(date +%s) - scan_start ))
      if [[ $scan_elapsed -ge $timeout_seconds ]]; then
        log_warn "Scan timeout, stopping..."
        zap_curl "${scan_api_url}/JSON/ascan/action/stop/?scanId=${scan_id}" >/dev/null
        break
      fi
      sleep 10
    done
    log_success "Active scan complete"
  fi

  # Export reports (copy from container)
  log_info "Exporting reports..."
  zap_curl "${scan_api_url}/OTHER/core/other/htmlreport/" > "${REPORT_HTML}"
  zap_curl "${scan_api_url}/JSON/core/view/alerts/" | jq '.' > "${REPORT_JSON}"
  zap_curl "${scan_api_url}/OTHER/core/other/xmlreport/" > "${REPORT_XML}"
}

# --- Wrapper-based scan (no auth) ---
run_wrapper_scan() {
  local docker_args=(
    --rm
    --platform "${DOCKER_PLATFORM}"
    --name "${ZAP_CONTAINER}"
    -v "${REPORT_DIR}:/zap/wrk:rw"
    -t "${ZAP_IMAGE}"
  )

  local zap_args=()

  case "$SCAN_TYPE" in
    full)
      zap_args=(
        zap-full-scan.py
        -t "${ZAP_TARGET}"
        -r zap-report.html
        -J zap-report.json
        -x zap-report.xml
        -l "${MIN_ALERT}"
        -I
        -z "-config spider.maxDuration=5 -config scanner.domxss.enabled=false"
      )
      ;;
    api)
      zap_args=(
        zap-api-scan.py
        -t "${ZAP_API_DOCS_URL}"
        -f openapi
        -r zap-report.html
        -J zap-report.json
        -x zap-report.xml
        -l "${MIN_ALERT}"
        -I
      )
      ;;
    *)
      log_error "Unknown scan type: ${SCAN_TYPE} (use 'full' or 'api')"
      exit 1
      ;;
  esac

  log_info "Running ZAP scan (this may take a while)..."
  docker run "${docker_args[@]}" "${zap_args[@]}" 2>&1 | tee "${REPORT_LOG}" || {
    log_warn "ZAP scan exited with non-zero code (may still have produced results)"
  }
}

# --- Helpers ---
parse_timeout() {
  local t="$1"
  t="${t%m}"  # remove trailing 'm'
  echo $((t * 60))
}

urlencode() {
  python3 -c "import urllib.parse; print(urllib.parse.quote('$1', safe=''))"
}

# --- Main ---
main() {
  log_info "=== ZAP Scan (${SCAN_TYPE}) ==="
  log_info "Target:     ${ZAP_TARGET}"
  log_info "Min alert:  ${MIN_ALERT}"
  log_info "Timeout:    ${TIMEOUT}"
  log_info "Auth:       ${AUTH_ENABLED}"
  log_info "Reports:    ${REPORT_DIR}"

  # Run scan
  if [[ "$AUTH_ENABLED" == true ]] && [[ "$SCAN_TYPE" == "full" ]]; then
    run_auth_scan
  elif [[ "$AUTH_ENABLED" == true ]] && [[ "$SCAN_TYPE" == "api" ]]; then
    log_warn "Auth is configured but API scan mode does not use authentication"
    run_wrapper_scan
  else
    run_wrapper_scan
  fi

  # Generate summary
  log_info "Generating summary..."
  if [[ -f "$REPORT_JSON" ]] && [[ -s "$REPORT_JSON" ]]; then
    {
      echo "=== ZAP Scan Summary ==="
      echo "Target: ${TARGET_URL}"
      echo "Type:   ${SCAN_TYPE}"
      echo "Date:   $(date '+%Y-%m-%d %H:%M:%S')"
      echo ""
      echo "--- Alerts by Risk Level ---"
      jq -r '
        [.alerts[]?] | group_by(.risk)
        | map({risk: .[0].risk, count: length})
        | sort_by(.risk)
        | .[]
        | "\(.risk): \(.count)"
      ' "${REPORT_JSON}" 2>/dev/null || echo "No alerts or parse error"
      echo ""
      echo "HTML report: ${REPORT_HTML}"
      echo "JSON report: ${REPORT_JSON}"
    } | tee "${REPORT_SUMMARY}"
  else
    echo "No results (check ${REPORT_LOG} for details)" | tee "${REPORT_SUMMARY}"
  fi

  log_success "=== ZAP scan complete ==="
  log_success "Summary: ${REPORT_SUMMARY}"
}

main
