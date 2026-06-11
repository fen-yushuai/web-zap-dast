#!/usr/bin/env bash
# Shared utility functions for DAST pipeline

set -euo pipefail

# --- Colors ---
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# --- Logging ---
_log() {
  local level="$1" color="$2"
  shift 2
  echo -e "${color}[$(date '+%H:%M:%S')] [${level}]${NC} $*"
}

log_info()    { _log "INFO"    "$BLUE"   "$@"; }
log_success() { _log "SUCCESS" "$GREEN"  "$@"; }
log_warn()    { _log "WARN"    "$YELLOW" "$@"; }
log_error()   { _log "ERROR"   "$RED"    "$@"; }

# --- Command check ---
check_command() {
  command -v "$1" &>/dev/null
}

# --- Wait for URL ---
wait_for_url() {
  local url="$1"
  local timeout_s="${2:-60}"
  local health_path="${3:-}"
  local target_url="${url}${health_path}"
  local elapsed=0

  log_info "Waiting for ${target_url} (timeout: ${timeout_s}s)..."
  while (( elapsed < timeout_s )); do
    if curl -sf -o /dev/null --max-time 5 "$target_url" 2>/dev/null; then
      log_success "Target is ready: ${target_url}"
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done

  log_error "Timeout after ${timeout_s}s waiting for ${target_url}"
  return 1
}

# --- Ensure directory ---
ensure_dir() {
  mkdir -p "$1"
}

# --- Cleanup on exit ---
cleanup_on_exit() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log_warn "Script exited with code ${exit_code}, running cleanup..."
  fi
}
