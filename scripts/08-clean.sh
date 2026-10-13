#!/usr/bin/env bash
# ==============================================================================
# 08-clean.sh - Clean workspace directories and temporary build artifacts
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/00-common.sh"

log_header "Cleaning Build Workspace"

if [[ "$1" == "--all" || "$1" == "-a" ]]; then
    log_info "Removing build workspace AND output artifacts..."
    rm -rf "${WORKSPACE_DIR}" "${OUTPUT_DIR}"
    log_success "Cleaned both ${WORKSPACE_DIR} and ${OUTPUT_DIR}."
else
    log_info "Removing build workspace (${WORKSPACE_DIR}). Keeping ${OUTPUT_DIR}..."
    rm -rf "${WORKSPACE_DIR}"
    log_success "Cleaned ${WORKSPACE_DIR}."
fi
