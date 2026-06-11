#!/usr/bin/env bash
# Nuclei scan wrapper (Docker-based)
# Usage: ./scripts/scan-nuclei.sh [--tags TAGS] [--severity LEVEL] [--rate-limit N]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/common.sh"

# --- Parse arguments ---
TAGS=""
SEVERITY="${NUCLEI_SEVERITY}"
RATE_LIMIT="${NUCLEI_RATE_LIMIT}"
REPORT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tags)       TAGS="$2"; shift 2 ;;
    --severity)   SEVERITY="$2"; shift 2 ;;
    --rate-limit) RATE_LIMIT="$2"; shift 2 ;;
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

REPORT_JSON="${REPORT_DIR}/nuclei-results.json"
REPORT_SARIF="${REPORT_DIR}/nuclei-results.sarif"
REPORT_LOG="${REPORT_DIR}/nuclei-output.log"
REPORT_SUMMARY="${REPORT_DIR}/nuclei-summary.txt"

NUCLEI_TARGET="${TARGET_URL}"

log_info "=== Nuclei Scan ==="
log_info "Target:     ${NUCLEI_TARGET}"
log_info "Severity:   ${SEVERITY}"
log_info "Rate limit: ${RATE_LIMIT}/s"
log_info "Reports:    ${REPORT_DIR}"

# --- Build command ---
if [[ -n "$NUCLEI_URL_LIST" ]]; then
  NUCLEI_ARGS=(-l /tmp/report/urls.txt)
else
  NUCLEI_ARGS=(-u "${NUCLEI_TARGET}")
fi

NUCLEI_ARGS+=(
  -severity "${SEVERITY}"
  -rl "${RATE_LIMIT}"
  -c "${NUCLEI_CONCURRENCY}"
  -timeout "${NUCLEI_TIMEOUT}"
  -jsonl -o /tmp/report/nuclei-results.json
  -sarif-export /tmp/report/nuclei-results.sarif
  -silent
  -no-color
)

if [[ -n "$TAGS" ]]; then
  NUCLEI_ARGS+=(-tags "$TAGS")
  log_info "Tags:       ${TAGS}"
fi

# --- Copy URL list if provided ---
if [[ -n "$NUCLEI_URL_LIST" ]]; then
  cp "$NUCLEI_URL_LIST" "${REPORT_DIR}/urls.txt"
fi

# --- Run scan ---
log_info "Running Nuclei scan..."
docker run --rm \
  --platform "${DOCKER_PLATFORM}" \
  --name "${NUCLEI_CONTAINER}" \
  -v "${HOME}/nuclei-templates:/root/nuclei-templates:ro" \
  -v "${REPORT_DIR}:/tmp/report:rw" \
  "${NUCLEI_IMAGE}" \
  "${NUCLEI_ARGS[@]}" \
  2>&1 | tee "${REPORT_LOG}"
NUCLEI_EXIT=${PIPESTATUS[0]}
if [[ $NUCLEI_EXIT -ge 2 ]]; then
  log_error "Nuclei scan failed (exit code: ${NUCLEI_EXIT})"
  exit 1
fi
if [[ $NUCLEI_EXIT -eq 1 ]]; then
  log_success "Nuclei found vulnerabilities"
else
  log_success "Nuclei scan completed (no findings)"
fi

# --- Generate summary ---
log_info "Generating summary..."
if [[ -f "$REPORT_JSON" ]] && [[ -s "$REPORT_JSON" ]]; then
  {
    echo "=== Nuclei Scan Summary ==="
    echo "Target: ${TARGET_URL}"
    echo "Date:   $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "--- Findings by Severity ---"
    jq -sr '
      group_by(.info.severity)
      | map({severity: .[0].info.severity, count: length})
      | .[]
      | "\(.severity): \(.count)"
    ' "${REPORT_JSON}" 2>/dev/null || echo "No findings or parse error"
    echo ""
    echo "Full report: ${REPORT_JSON}"
    echo "SARIF report: ${REPORT_SARIF}"
  } | tee "${REPORT_SUMMARY}"
else
  echo "No findings" | tee "${REPORT_SUMMARY}"
fi

log_success "=== Nuclei scan complete ==="
log_success "Summary: ${REPORT_SUMMARY}"
