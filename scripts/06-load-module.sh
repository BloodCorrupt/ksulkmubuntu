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
if is_module_loaded "kernelsu"; then
    log_warn "kernelsu is ALREADY loaded and active in the kernel!"
    grep -E "^kernelsu\b" /proc/modules 2>/dev/null || true
    echo ""
    read -rp "Do you want to unload and reload it? [y/N]: " RELOAD_CHOICE
    if [[ "${RELOAD_CHOICE}" =~ ^[Yy]$ ]]; then
        log_info "Attempting to unload existing kernelsu module..."
        ${SUDO_CMD} rmmod kernelsu 2>/dev/null || ${SUDO_CMD} modprobe -r kernelsu 2>/dev/null || log_warn "Could not rmmod kernelsu (module may be in use by active hooks)."
    else
        log_info "Keeping currently loaded module."
        exit 0
    fi
fi

LOAD_ARGS=()
if [[ -n "${CONTAINER_MANAGER_UID:-}" ]]; then
    LOAD_ARGS+=("manager_uid=${CONTAINER_MANAGER_UID}")
fi

log_step "Executing lkmloader to resolve unexported symbols and load module..."
log_info "Command: ${SUDO_CMD} ${LOADER_PATH} ${MODULE_PATH} ${LOAD_ARGS[*]}"

LOAD_OUTPUT=$(${SUDO_CMD} "${LOADER_PATH}" "${MODULE_PATH}" "${LOAD_ARGS[@]}" 2>&1)
LOAD_STATUS=$?

echo "${LOAD_OUTPUT}"

# Check for successful loading:
# Note: In modern kmod, 'lsmod' may complain about missing '/sys/module/kernelsu/holders'
# because it was loaded dynamically via memfd/init_module, so we verify via /proc/modules and sysfs directly.
if [[ ${LOAD_STATUS} -eq 0 ]] || is_module_loaded "kernelsu"; then
    echo ""
    log_success "KernelSU module is LOADED and ACTIVE in the kernel!"
    echo -e "\n${BOLD}Kernel Module Status:${NC}"
    if grep -E "^kernelsu\b" /proc/modules 2>/dev/null; then
        grep -E "^kernelsu\b" /proc/modules
    elif [[ -d /sys/module/kernelsu ]]; then
        echo "Module entry active in /sys/module/kernelsu"
    fi

    # Set manager UID if parameter exposed
    if [[ -f "/sys/module/kernelsu/parameters/manager_uid" && -n "${CONTAINER_MANAGER_UID:-}" ]]; then
        echo "${CONTAINER_MANAGER_UID}" | ${SUDO_CMD} tee /sys/module/kernelsu/parameters/manager_uid >/dev/null || true
        log_info "Manager UID parameter set to: $(cat /sys/module/kernelsu/parameters/manager_uid 2>/dev/null)"
    fi

    echo -e "\n${BOLD}Recent Kernel Messages (dmesg):${NC}"
    ${SUDO_CMD} dmesg | grep -iE "(kernelsu|ksu)" | tail -n 12 || true
    echo ""
    log_info "Tip: In Redroid or Waydroid, ensure the Manager APK is installed (UID ${CONTAINER_MANAGER_UID:-10091})."
    log_info "If using Redroid, run scripts/09-setup-redroid.sh to bind-mount container /data to host."
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
