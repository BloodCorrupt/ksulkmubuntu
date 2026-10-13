#!/usr/bin/env bash
# ==============================================================================
# 00-common.sh - Shared utility functions and environment initialization
# ==============================================================================

set -o pipefail

# ANSI color codes
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Base directory determination
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load configuration if present
if [[ -f "${ROOT_DIR}/config.env" ]]; then
    # shellcheck source=/dev/null
    source "${ROOT_DIR}/config.env"
fi

# Fallback defaults if not set in config.env
KSU_GIT_REPO="${KSU_GIT_REPO:-https://github.com/KernelSU-Next/KernelSU-Next.git}"
KSU_GIT_BRANCH="${KSU_GIT_BRANCH:-dev}"
LKMLOADER_RELEASE_URL="${LKMLOADER_RELEASE_URL:-https://github.com/maxsteeel/lkmloader/releases/download/v1.0.0/lkmloader-x86_64}"
LKMLOADER_SHA256="${LKMLOADER_SHA256:-ea0a460350ccaaa9671cf1e3bd764f2421bec5a1948a21f0c85a3b4f06eaaba2}"
KERNEL_CDN_BASE="${KERNEL_CDN_BASE:-https://cdn.kernel.org/pub/linux/kernel}"
INSTALL_DIR="${INSTALL_DIR:-/opt/kernelsu}"
WORKSPACE_DIR="${ROOT_DIR}/${WORKSPACE_DIR:-build_workspace}"
OUTPUT_DIR="${ROOT_DIR}/${OUTPUT_DIR:-output}"

log_header() {
    echo -e "\n${BOLD}${CYAN}======================================================================${NC}"
    echo -e "${BOLD}${CYAN}  $*${NC}"
    echo -e "${BOLD}${CYAN}======================================================================${NC}\n"
}

log_step() {
    echo -e "${BOLD}${BLUE}==>${NC} ${BOLD}$*${NC}"
}

log_info() {
    echo -e "${CYAN}[*]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[+]${NC} ${BOLD}$*${NC}"
}

log_warn() {
    echo -e "${YELLOW}[!] WARNING:${NC} $*"
}

log_error() {
    echo -e "${RED}[-] ERROR:${NC} ${BOLD}$*${NC}" >&2
}

log_fatal() {
    echo -e "\n${RED}${BOLD}[FATAL] $*${NC}\n" >&2
    exit 1
}

check_root_or_sudo() {
    if [[ $EUID -ne 0 ]]; then
        if ! command -v sudo &>/dev/null; then
            log_fatal "This step requires root privileges and 'sudo' is not installed."
        fi
        if ! sudo -v &>/dev/null; then
            log_fatal "User does not have sudo privileges."
        fi
        SUDO_CMD="sudo"
    else
        SUDO_CMD=""
    fi
}

ensure_dirs() {
    mkdir -p "${WORKSPACE_DIR}" "${OUTPUT_DIR}"
}
