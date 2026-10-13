#!/usr/bin/env bash
# ==============================================================================
# 07-systemd-service.sh - Install / Uninstall systemd service for boot loading
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/00-common.sh"

log_header "Configuring Persistent Boot Service (systemd)"

check_root_or_sudo

SERVICE_FILE="/etc/systemd/system/kernelsu-lkm.service"

if [[ "$1" == "--uninstall" || "$1" == "-u" ]]; then
    log_step "Uninstalling kernelsu-lkm systemd service..."
    if systemctl is-enabled kernelsu-lkm.service &>/dev/null; then
        ${SUDO_CMD} systemctl disable kernelsu-lkm.service
    fi
    ${SUDO_CMD} systemctl stop kernelsu-lkm.service 2>/dev/null || true
    ${SUDO_CMD} rm -f "${SERVICE_FILE}"
    ${SUDO_CMD} systemctl daemon-reload
    ${SUDO_CMD} rm -rf "${INSTALL_DIR}"
    log_success "kernelsu-lkm boot service uninstalled."
    exit 0
fi

MODULE_PATH="${OUTPUT_DIR}/kernelsu.ko"
LOADER_PATH="${OUTPUT_DIR}/lkmloader-x86_64"

if [[ ! -f "${MODULE_PATH}" || ! -x "${LOADER_PATH}" ]]; then
    log_fatal "Compiled module (${MODULE_PATH}) or loader (${LOADER_PATH}) missing! Run build steps first."
fi

log_step "Installing persistent files to ${INSTALL_DIR}..."
${SUDO_CMD} mkdir -p "${INSTALL_DIR}"
${SUDO_CMD} cp -f "${MODULE_PATH}" "${INSTALL_DIR}/kernelsu.ko"
${SUDO_CMD} cp -f "${LOADER_PATH}" "${INSTALL_DIR}/lkmloader-x86_64"
${SUDO_CMD} chmod 755 "${INSTALL_DIR}/lkmloader-x86_64"
${SUDO_CMD} chmod 644 "${INSTALL_DIR}/kernelsu.ko"

log_step "Installing systemd unit to ${SERVICE_FILE}..."
${SUDO_CMD} cp -f "${ROOT_DIR}/systemd/kernelsu-lkm.service" "${SERVICE_FILE}"
${SUDO_CMD} chmod 644 "${SERVICE_FILE}"

log_step "Reloading systemd and enabling service on boot..."
${SUDO_CMD} systemctl daemon-reload
${SUDO_CMD} systemctl enable kernelsu-lkm.service

log_step "Testing systemd service activation..."
${SUDO_CMD} systemctl restart kernelsu-lkm.service

echo ""
if systemctl is-active kernelsu-lkm.service &>/dev/null; then
    log_success "kernelsu-lkm.service is ACTIVE and enabled for boot startup!"
    ${SUDO_CMD} systemctl status kernelsu-lkm.service --no-pager
else
    log_warn "Service was installed, but status is not active. Check: journalctl -u kernelsu-lkm.service"
fi
