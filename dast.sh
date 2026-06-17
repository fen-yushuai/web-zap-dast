#!/usr/bin/env bash
# DAST Pipeline - Main orchestration script
# Usage:
#   ./dast.sh                    # Full pipeline (Spider + ZAP scan)
#   ./dast.sh --setup            # Install dependencies only
#   ./dast.sh --scan spider      # Run spider reconnaissance only
#   ./dast.sh --scan zap         # Run ZAP scan only
#   ./dast.sh --report-only DIR  # Regenerate report from existing data

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/scripts/lib/config.sh"
source "${SCRIPT_DIR}/scripts/lib/common.sh"

# --- Parse arguments ---
SETUP_ONLY=false
SCAN_ONLY=""
REPORT_ONLY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --setup)       SETUP_ONLY=true; shift ;;
    --scan)        SCAN_ONLY="$2"; shift 2 ;;
    --report-only) REPORT_ONLY="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--setup] [--scan spider|zap] [--report-only DIR]"
      exit 0
      ;;
    *) log_error "Unknown option: $1"; exit 1 ;;
  esac
done

# --- Step 1: Setup check ---
step_setup() {
  log_info "Step 1: Checking dependencies..."
  if [[ -z "$TARGET_URL" ]]; then
    log_error "TARGET_URL is not set. Edit config.sh first."
    exit 1
  fi
  if ! check_command docker || ! docker info &>/dev/null; then
    log_error "Docker not available. Run: ./scripts/setup.sh"
    exit 1
  fi
  if ! docker image inspect "${ZAP_IMAGE}" &>/dev/null; then
    log_error "ZAP image not found. Run: ./scripts/setup.sh"
    exit 1
  fi
  log_success "All dependencies ready"
}

# --- Main flow ---
main() {
  log_info "=========================================="
  log_info "  DAST Pipeline"
  log_info "=========================================="

  # Setup only
  if [[ "$SETUP_ONLY" == true ]]; then
    "${SCRIPT_DIR}/scripts/setup.sh"
    exit 0
  fi

  # Report only
  if [[ -n "$REPORT_ONLY" ]]; then
    "${SCRIPT_DIR}/scripts/report.sh" "$REPORT_ONLY"
    exit 0
  fi

  # Full pipeline or single scan
  step_setup

  # Create shared report directory
  REPORT_DIR="${REPORTS_DIR}/$(date +%Y%m%d_%H%M%S)"
  ensure_dir "${REPORT_DIR}"

  # Scans
  SPIDER_OK=true
  ZAP_OK=true

  if [[ -z "$SCAN_ONLY" ]] || [[ "$SCAN_ONLY" == "spider" ]]; then
    log_info "Running Spider reconnaissance..."
    if "${SCRIPT_DIR}/scripts/zap-spider.sh" --report-dir "${REPORT_DIR}"; then
      log_success "Spider reconnaissance completed"
    else
      log_error "Spider reconnaissance failed"
      SPIDER_OK=false
    fi
  fi

  if [[ -z "$SCAN_ONLY" ]] || [[ "$SCAN_ONLY" == "zap" ]]; then
    log_info "Running ZAP scan..."
    if "${SCRIPT_DIR}/scripts/scan-zap.sh" --report-dir "${REPORT_DIR}"; then
      log_success "ZAP scan completed"
    else
      log_error "ZAP scan failed"
      ZAP_OK=false
    fi
  fi

  # Generate report
  log_info "Generating report..."
  "${SCRIPT_DIR}/scripts/report.sh" "${REPORT_DIR}"

  # Final summary
  echo ""
  log_info "=========================================="
  log_info "  Pipeline Complete"
  log_info "=========================================="
  log_info "Report: ${REPORT_DIR}"
  [[ "$SPIDER_OK" == true ]] && log_success "Spider: OK" || log_error "Spider: FAILED"
  [[ "$ZAP_OK" == true ]]    && log_success "ZAP:    OK" || log_error "ZAP:    FAILED"
}

main
