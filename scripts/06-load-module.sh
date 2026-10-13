#!/usr/bin/env bash
# ==============================================================================
# 06-load-module.sh - Load KernelSU LKM using lkmloader-x86_64
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/00-common.sh"

log_header "Loading KernelSU-Next LKM into Running Kernel"

check_root_or_sudo

MODULE_PATH="${OUTPUT_DIR}/kernelsu.ko"
LOADER_PATH="${OUTPUT_DIR}/lkmloader-x86_64"

if [[ ! -f "${MODULE_PATH}" ]]; then
    log_fatal "Module ${MODULE_PATH} not found. Run 04-build-ksu.sh first!"
fi

if [[ ! -x "${LOADER_PATH}" ]]; then
    log_fatal "Loader ${LOADER_PATH} not found or not executable. Run 05-fetch-lkmloader.sh first!"
fi

# Check if already loaded
if lsmod | grep -q "^kernelsu\b"; then
    log_warn "kernelsu is ALREADY loaded in the kernel!"
    lsmod | grep "^kernelsu\b"
    echo ""
    read -rp "Do you want to unload and reload it? [y/N]: " RELOAD_CHOICE
    if [[ "${RELOAD_CHOICE}" =~ ^[Yy]$ ]]; then
        log_info "Unloading existing kernelsu module..."
        ${SUDO_CMD} rmmod kernelsu || log_fatal "Failed to unload existing kernelsu module."
    else
        log_info "Keeping currently loaded module."
        exit 0
    fi
fi

log_step "Executing lkmloader to resolve unexported symbols and load module..."
log_info "Command: ${SUDO_CMD} ${LOADER_PATH} ${MODULE_PATH}"

LOAD_OUTPUT=$(${SUDO_CMD} "${LOADER_PATH}" "${MODULE_PATH}" 2>&1)
LOAD_STATUS=$?

echo "${LOAD_OUTPUT}"

if [[ ${LOAD_STATUS} -eq 0 ]] && lsmod | grep -q "^kernelsu\b"; then
    echo ""
    log_success "KernelSU module loaded successfully into the active kernel!"
    echo -e "\n${BOLD}Kernel Module Status:${NC}"
    lsmod | grep "^kernelsu\b"

    echo -e "\n${BOLD}Recent Kernel Messages (dmesg):${NC}"
    ${SUDO_CMD} dmesg | grep -iE "(kernelsu|ksu)" | tail -n 12 || true
    echo ""
    log_info "Tip: In Waydroid or your container environment, install the KernelSU-Next Manager APK"
    log_info "to manage root permissions, su binaries, and overlayfs modules."
else
    echo ""
    log_error "Failed to load kernelsu.ko (Exit code: ${LOAD_STATUS})."
    
    echo -e "\n${BOLD}Diagnostic details from dmesg:${NC}"
    ${SUDO_CMD} dmesg | tail -n 15

    echo -e "\n${YELLOW}${BOLD}Troubleshooting suggestions:${NC}"
    echo -e " 1. ${BOLD}Lockdown / Secure Boot:${NC} If you see 'Lockdown: ... integrity', Secure Boot is blocking"
    echo -e "    unsigned module loading. Disable Secure Boot in UEFI/BIOS or sign kernelsu.ko with MOK."
    echo -e " 2. ${BOLD}Vermagic mismatch:${NC} If the kernel strictly enforces vermagic, ensure your"
    echo -e "    headers exactly match 'uname -r'."
    echo -e " 3. ${BOLD}/dev/kmsg permissions:${NC} lkmloader needs sudo access to /dev/kmsg to read kernel vermagic logs."
    exit 1
fi
