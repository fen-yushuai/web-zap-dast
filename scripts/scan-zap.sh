#!/usr/bin/env bash
# OWASP ZAP scan wrapper
# Usage: ./scripts/scan-zap.sh [--scan-type full|api] [--timeout DURATION] [--min-alert LEVEL]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/common.sh"

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


log_info "=== ZAP Scan (${SCAN_TYPE}) ==="
log_info "Target:     ${ZAP_TARGET}"
log_info "Min alert:  ${MIN_ALERT}"
log_info "Timeout:    ${TIMEOUT}"
log_info "Reports:    ${REPORT_DIR}"

# --- Build command ---
DOCKER_ARGS=(
  --rm
  --platform "${DOCKER_PLATFORM}"
  --name "${ZAP_CONTAINER}"
  -v "${REPORT_DIR}:/zap/wrk:rw"
  -t "${ZAP_IMAGE}"
)

ZAP_ARGS=()

case "$SCAN_TYPE" in
  full)
    ZAP_ARGS=(
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
    ZAP_ARGS=(
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

# --- Run scan ---
log_info "Running ZAP scan (this may take a while)..."
docker run "${DOCKER_ARGS[@]}" "${ZAP_ARGS[@]}" 2>&1 | tee "${REPORT_LOG}" || {
  log_warn "ZAP scan exited with non-zero code (may still have produced results)"
}

# --- Generate summary ---
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
      [.site[]?.alerts[]?] | group_by(.riskdesc)
      | map({risk: .[0].riskdesc, count: length})
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
