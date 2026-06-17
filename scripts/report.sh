#!/usr/bin/env bash
# Report aggregation script
# Usage: ./scripts/report.sh [REPORT_DIR]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/common.sh"

# --- Determine report directory ---
REPORT_DIR="${1:-}"
if [[ -z "$REPORT_DIR" ]]; then
  # Use latest report directory
  REPORT_DIR=$(ls -dt "${REPORTS_DIR}"/*/ 2>/dev/null | head -1 || true)
  if [[ -z "$REPORT_DIR" ]]; then
    log_error "No report directories found in ${REPORTS_DIR}"
    exit 1
  fi
fi

REPORT_DIR="${REPORT_DIR%/}"
SUMMARY="${REPORT_DIR}/summary.md"

log_info "=== Generating Combined Report ==="
log_info "Report dir: ${REPORT_DIR}"

# --- Build summary ---
{
  echo "# DAST Scan Report"
  echo ""
  echo "- **Date**: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "- **Target**: ${TARGET_URL}"
  echo "- **Directory**: ${REPORT_DIR}"
  echo ""

  # Spider section
  echo "## Spider Reconnaissance"
  echo ""
  if [[ -f "${REPORT_DIR}/zap-spider-summary.txt" ]]; then
    sed -n '/^--- Results ---$/,/^--- Configuration ---$/p' "${REPORT_DIR}/zap-spider-summary.txt" | grep -v "^---" | grep -v "^$" || echo "No results"
  else
    echo "_Spider not run or no results_"
  fi
  echo ""

  # ZAP section
  echo "## ZAP Findings"
  echo ""
  if [[ -f "${REPORT_DIR}/zap-summary.txt" ]]; then
    sed -n '/Alerts by Risk Level/,/^$/p' "${REPORT_DIR}/zap-summary.txt" | grep -v "Alerts by Risk Level" | grep -v "^$" || echo "No alerts"
    echo ""
    echo "Full report: \`zap-report.html\` / \`zap-report.json\`"
  else
    echo "_Scan not run or no results_"
  fi
  echo ""

  # File listing
  echo "## Report Files"
  echo ""
  echo "| File | Description |"
  echo "|------|-------------|"
  echo "| \`zap-spider-urls.txt\` | Spider discovered URLs |"
  echo "| \`zap-sitemap.txt\` | Site tree structure |"
  echo "| \`zap-report.html\` | ZAP report (HTML) |"
  echo "| \`zap-report.json\` | ZAP findings (JSON) |"
  echo "| \`zap-report.xml\` | ZAP findings (XML) |"
} > "${SUMMARY}"

log_success "=== Report generated ==="
log_success "Summary: ${SUMMARY}"
echo ""
cat "${SUMMARY}"
