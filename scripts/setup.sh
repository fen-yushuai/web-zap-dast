#!/usr/bin/env bash
# Dependency check and installation for DAST pipeline
# Usage: ./scripts/setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/common.sh"

log_info "=== DAST Pipeline Setup ==="

# --- Docker ---
log_info "Checking Docker..."
if ! check_command docker; then
  log_error "Docker not found. Install Docker first."
  exit 1
fi
if ! docker info &>/dev/null; then
  log_error "Docker daemon not running. Start Docker first."
  exit 1
fi
log_success "Docker: $(docker --version)"

# --- Python 3 (required for urlencode) ---
log_info "Checking Python 3..."
if ! check_command python3; then
  log_error "python3 not found. Install Python 3 first."
  exit 1
fi
log_success "Python: $(python3 --version)"

# --- ZAP (Docker) ---
log_info "Pulling ZAP Docker image..."
docker pull --platform "${DOCKER_PLATFORM}" "${ZAP_IMAGE}"
log_success "ZAP image ready: ${ZAP_IMAGE}"

# --- Reports directory ---
ensure_dir "${REPORTS_DIR}"
log_success "Reports directory: ${REPORTS_DIR}"

log_success "=== Setup complete ==="
