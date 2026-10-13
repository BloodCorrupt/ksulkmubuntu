#!/usr/bin/env bash
# ==============================================================================
# 02-install-deps.sh - Install kernel building tools and headers on Ubuntu
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/00-common.sh"

log_header "Installing Dependencies & Kernel Headers"

check_root_or_sudo

KERNEL_RELEASE="$(uname -r)"

log_step "Updating APT package cache..."
${SUDO_CMD} apt-get update -y

PACKAGES=(
    build-essential
    "linux-headers-${KERNEL_RELEASE}"
    libelf-dev
    bison
    flex
    libssl-dev
    bc
    rsync
    curl
    wget
    git
    tar
    xz-utils
    kmod
    ca-certificates
    mokutil
    pkg-config
)

log_step "Installing required compilation packages..."
${SUDO_CMD} DEBIAN_FRONTEND=noninteractive apt-get install -y "${PACKAGES[@]}"

KERNEL_BUILD_DIR="/lib/modules/${KERNEL_RELEASE}/build"

if [[ ! -d "${KERNEL_BUILD_DIR}" ]]; then
    log_warn "${KERNEL_BUILD_DIR} is still missing. Attempting 'linux-headers-generic'..."
    ${SUDO_CMD} DEBIAN_FRONTEND=noninteractive apt-get install -y linux-headers-generic
fi

if [[ ! -d "${KERNEL_BUILD_DIR}" ]]; then
    log_fatal "Kernel headers could not be found at ${KERNEL_BUILD_DIR}. Please ensure matching headers are installed!"
fi

log_success "Kernel headers verified at: ${KERNEL_BUILD_DIR}"
log_info "Compiler version: $(gcc --version | head -n 1)"
log_info "Make version: $(make --version | head -n 1)"
log_success "All dependencies installed successfully!"
