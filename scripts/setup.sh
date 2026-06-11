#!/usr/bin/env bash
# Dependency check and installation for DAST pipeline
# Usage: ./scripts/setup.sh [--skip-update]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/config.sh"
source "${SCRIPT_DIR}/lib/common.sh"

SKIP_UPDATE=false
[[ "${1:-}" == "--skip-update" ]] && SKIP_UPDATE=true

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

# --- Nuclei (Docker) ---
log_info "Pulling Nuclei Docker image..."
docker pull --platform "${DOCKER_PLATFORM}" "${NUCLEI_IMAGE}"
log_success "Nuclei image ready: ${NUCLEI_IMAGE}"

if [[ "$SKIP_UPDATE" == false ]]; then
  log_info "Updating Nuclei templates..."
  docker run --rm --platform "${DOCKER_PLATFORM}" -v "${HOME}/nuclei-templates:/root/nuclei-templates" "${NUCLEI_IMAGE}" -update-templates -silent
  log_success "Nuclei templates updated"
else
  log_warn "Skipping Nuclei template update (--skip-update)"
fi

# --- ZAP (Docker) ---
log_info "Pulling ZAP Docker image..."
docker pull --platform "${DOCKER_PLATFORM}" "${ZAP_IMAGE}"
log_success "ZAP image ready: ${ZAP_IMAGE}"

# --- Reports directory ---
ensure_dir "${REPORTS_DIR}"
log_success "Reports directory: ${REPORTS_DIR}"

log_success "=== Setup complete ==="
