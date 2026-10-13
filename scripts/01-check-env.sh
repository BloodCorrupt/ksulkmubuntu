#!/usr/bin/env bash
# ==============================================================================
# 01-check-env.sh - Environment audit and pre-flight checks
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/00-common.sh"

log_header "Pre-flight Environment Check"

FAIL_COUNT=0
WARN_COUNT=0

# 1. Architecture Check
ARCH="$(uname -m)"
log_info "Architecture: ${BOLD}${ARCH}${NC}"
if [[ "${ARCH}" != "x86_64" ]]; then
    log_warn "Target system architecture is '${ARCH}', but this builder suite is specifically tuned for x86_64!"
    ((WARN_COUNT++))
else
    log_success "Architecture is x86_64."
fi

# 2. Operating System Check
if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    OS_NAME="${PRETTY_NAME:-$NAME}"
    log_info "Operating System: ${BOLD}${OS_NAME}${NC}"
else
    OS_NAME="$(uname -s)"
    log_warn "Could not read /etc/os-release. Detected: ${OS_NAME}"
    ((WARN_COUNT++))
fi

# 3. Kernel Version Check
KERNEL_RELEASE="$(uname -r)"
log_info "Active Kernel Release: ${BOLD}${KERNEL_RELEASE}${NC}"

KERNEL_BUILD_DIR="/lib/modules/${KERNEL_RELEASE}/build"
if [[ -d "${KERNEL_BUILD_DIR}" ]]; then
    log_success "Kernel build headers directory found: ${KERNEL_BUILD_DIR}"
else
    log_warn "Kernel headers missing at ${KERNEL_BUILD_DIR}."
    log_info "Run step '02-install-deps.sh' to install linux-headers-${KERNEL_RELEASE}."
    ((WARN_COUNT++))
fi

# 4. Check Root / Sudo privileges
check_root_or_sudo
if [[ -n "${SUDO_CMD}" ]]; then
    log_success "Sudo privileges confirmed."
else
    log_success "Running directly as root."
fi

# 5. Check Disk Space in current directory
FREE_SPACE_KB=$(df -k . | awk 'NR==2 {print $4}')
FREE_SPACE_GB=$((FREE_SPACE_KB / 1024 / 1024))
log_info "Free disk space in current filesystem: ${BOLD}${FREE_SPACE_GB} GB${NC}"
if [[ ${FREE_SPACE_GB} -lt 4 ]]; then
    log_warn "Low disk space (< 4 GB). Downloading and extracting kernel source may require 3-5 GB."
    ((WARN_COUNT++))
else
    log_success "Sufficient disk space available."
fi

# 6. Check Secure Boot Status
log_info "Checking UEFI Secure Boot status..."
SB_STATE="unknown"
if command -v mokutil &>/dev/null; then
    MOK_OUT=$(mokutil --sb-state 2>/dev/null || true)
    if echo "${MOK_OUT}" | grep -qi "SecureBoot enabled"; then
        SB_STATE="enabled"
    elif echo "${MOK_OUT}" | grep -qi "SecureBoot disabled"; then
        SB_STATE="disabled"
    fi
elif [[ -d /sys/firmware/efi ]]; then
    if od -An -t u1 /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null | grep -q "1$"; then
        SB_STATE="enabled"
    else
        SB_STATE="disabled"
    fi
else
    SB_STATE="not_efi"
fi

if [[ "${SB_STATE}" == "enabled" ]]; then
    log_warn "${BOLD}UEFI Secure Boot is ENABLED!${NC}"
    echo -e "    ${YELLOW}When Secure Boot is active, the Linux kernel operates in lockdown mode${NC}"
    echo -e "    ${YELLOW}and will reject unsigned out-of-tree kernel modules (init_module blocked).${NC}"
    echo -e "    ${YELLOW}Action recommended: Disable Secure Boot in BIOS/UEFI settings, or sign${NC}"
    echo -e "    ${YELLOW}the resulting module with MOK (Machine Owner Key).${NC}"
    ((WARN_COUNT++))
elif [[ "${SB_STATE}" == "disabled" ]]; then
    log_success "Secure Boot is disabled (Unsigned kernel modules can be loaded)."
elif [[ "${SB_STATE}" == "not_efi" ]]; then
    log_info "Legacy BIOS boot detected (Secure Boot not applicable)."
else
    log_info "Secure Boot status could not be determined automatically."
fi

# 7. Check /dev/kmsg access
if [[ -r /dev/kmsg ]] || [[ $EUID -eq 0 ]] || sudo test -r /dev/kmsg; then
    log_success "/dev/kmsg is accessible (Required by lkmloader for vermagic auto-matching)."
else
    log_warn "/dev/kmsg is not directly readable. lkmloader requires root/sudo."
fi

# 8. Check /proc/kallsyms access
if [[ -r /proc/kallsyms ]]; then
    log_success "/proc/kallsyms is accessible (Required for runtime symbol resolution)."
else
    log_warn "/proc/kallsyms could not be read."
    ((WARN_COUNT++))
fi

echo ""
if [[ ${FAIL_COUNT} -eq 0 && ${WARN_COUNT} -eq 0 ]]; then
    log_success "Environment pre-flight checks passed with zero issues!"
else
    log_info "Pre-flight check summary: ${FAIL_COUNT} critical failures, ${WARN_COUNT} warnings."
fi
