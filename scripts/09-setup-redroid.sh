#!/usr/bin/env bash
# ==============================================================================
# 09-setup-redroid.sh - Link Redroid container /data to host for KernelSU / SukiSU
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/00-common.sh"

log_header "Redroid Container /data Host Link Helper"

check_root_or_sudo

if ! command -v docker &>/dev/null; then
    log_fatal "'docker' command not found. Please ensure Docker is installed."
fi

# 1. Detect Redroid Container
log_step "Detecting active Redroid container..."

CONTAINER_ID=""
CONTAINER_NAME="${REDROID_CONTAINER_NAME:-redroid13_x86_64}"

if ${SUDO_CMD} docker ps --format '{{.Names}}' | grep -q -E "^${CONTAINER_NAME}$"; then
    CONTAINER_ID=$(${SUDO_CMD} docker ps -q -f "name=^${CONTAINER_NAME}$")
    log_info "Found configured container: ${CONTAINER_NAME} (${CONTAINER_ID})"
else
    # Auto-detect any container running a redroid image
    DETECTED_CONTAINER=$(${SUDO_CMD} docker ps --filter "ancestor=redroid/redroid" --format '{{.ID}} {{.Names}}' | head -n 1)
    if [[ -z "${DETECTED_CONTAINER}" ]]; then
        # Search by image name containing redroid
        DETECTED_CONTAINER=$(${SUDO_CMD} docker ps --format '{{.ID}} {{.Names}} {{.Image}}' | grep -i "redroid" | head -n 1 || true)
    fi

    if [[ -n "${DETECTED_CONTAINER}" ]]; then
        CONTAINER_ID=$(echo "${DETECTED_CONTAINER}" | awk '{print $1}')
        CONTAINER_NAME=$(echo "${DETECTED_CONTAINER}" | awk '{print $2}')
        log_info "Auto-detected running Redroid container: ${CONTAINER_NAME} (${CONTAINER_ID})"
    fi
fi

if [[ -z "${CONTAINER_ID}" ]]; then
    log_warn "No active Redroid Docker container was detected running."
    echo ""
    read -rp "Enter container name or custom host path to Redroid's data directory: " USER_INPUT
    if [[ -d "${USER_INPUT}" ]]; then
        TARGET_DATA_DIR="${USER_INPUT}"
    elif ${SUDO_CMD} docker ps -a --format '{{.Names}}' | grep -q -E "^${USER_INPUT}$"; then
        CONTAINER_NAME="${USER_INPUT}"
        CONTAINER_ID=$(${SUDO_CMD} docker ps -a -q -f "name=^${CONTAINER_NAME}$")
    else
        log_fatal "Could not locate container or directory: '${USER_INPUT}'"
    fi
fi

# 2. Resolve /data storage path on host
if [[ -z "${TARGET_DATA_DIR:-}" && -n "${CONTAINER_ID}" ]]; then
    log_step "Locating container /data mount point on host..."

    # Check Docker inspect Mounts
    HOST_BIND=$(${SUDO_CMD} docker inspect "${CONTAINER_ID}" --format '{{range .Mounts}}{{if eq .Destination "/data"}}{{.Source}}{{end}}{{end}}' 2>/dev/null || true)

    if [[ -n "${HOST_BIND}" && -d "${HOST_BIND}" ]]; then
        TARGET_DATA_DIR="${HOST_BIND}"
        log_info "Found host mount for /data: ${TARGET_DATA_DIR}"
    else
        # Check overlay2 merged directory
        MERGED_DIR=$(${SUDO_CMD} docker inspect "${CONTAINER_ID}" --format '{{.GraphDriver.Data.MergedDir}}' 2>/dev/null || true)
        if [[ -n "${MERGED_DIR}" && -d "${MERGED_DIR}/data" ]]; then
            TARGET_DATA_DIR="${MERGED_DIR}/data"
            log_info "Found overlay2 container data path: ${TARGET_DATA_DIR}"
        fi
    fi
fi

if [[ -z "${TARGET_DATA_DIR:-}" || ! -d "${TARGET_DATA_DIR}" ]]; then
    log_fatal "Could not determine host directory for Redroid's /data!"
fi

log_info "Target Redroid Data Directory: ${TARGET_DATA_DIR}"

# 3. Inspect packages.list for Manager UID
PACKAGES_LIST="${TARGET_DATA_DIR}/system/packages.list"
DETECTED_UID=""

if [[ -f "${PACKAGES_LIST}" ]]; then
    log_success "Found /system/packages.list in data directory!"
    MANAGER_LINE=$(grep -E "(com\.rifsxd\.ksunext|me\.weishu\.kernelsu|org\.sukisu)" "${PACKAGES_LIST}" 2>/dev/null || true)
    if [[ -n "${MANAGER_LINE}" ]]; then
        DETECTED_PKG=$(echo "${MANAGER_LINE}" | awk '{print $1}')
        DETECTED_UID=$(echo "${MANAGER_LINE}" | awk '{print $2}')
        log_success "Found Manager Package: ${DETECTED_PKG} (UID: ${DETECTED_UID})"
    else
        log_warn "Manager package not yet present in packages.list (install the APK in Redroid)."
    fi
else
    log_warn "${PACKAGES_LIST} does not exist yet. Ensure Redroid has finished booting."
fi

EFFECTIVE_UID="${DETECTED_UID:-${CONTAINER_MANAGER_UID:-10091}}"

# 4. Bind-Mount to Host /data
log_step "Setting up /data host bind-mount..."

${SUDO_CMD} mkdir -p /data

if mountpoint -q /data; then
    CURRENT_MOUNT=$(${SUDO_CMD} findmnt -n -o SOURCE /data 2>/dev/null || true)
    log_info "Host /data is currently mounted from: ${CURRENT_MOUNT}"
    if [[ "${CURRENT_MOUNT}" != "${TARGET_DATA_DIR}"* ]]; then
        log_warn "Re-mounting /data to ${TARGET_DATA_DIR}..."
        ${SUDO_CMD} mount --bind "${TARGET_DATA_DIR}" /data
    else
        log_success "Host /data is already correctly bind-mounted to Redroid data!"
    fi
else
    log_info "Mounting ${TARGET_DATA_DIR} to /data..."
    ${SUDO_CMD} mount --bind "${TARGET_DATA_DIR}" /data
    log_success "Successfully bind-mounted /data!"
fi

# Verify host access
if [[ -f "/data/system/packages.list" ]]; then
    log_success "Verified: Host kernel can now read /data/system/packages.list directly!"
else
    log_warn "Host /data is mounted, but /data/system/packages.list is still pending creation by Android init."
fi

# 5. Configure KernelSU Manager UID in Sysfs (if loaded)
if is_module_loaded "kernelsu"; then
    if [[ -f "/sys/module/kernelsu/parameters/manager_uid" ]]; then
        echo "${EFFECTIVE_UID}" | ${SUDO_CMD} tee /sys/module/kernelsu/parameters/manager_uid >/dev/null || true
        log_success "Set /sys/module/kernelsu/parameters/manager_uid = ${EFFECTIVE_UID}"
    fi

    # Trigger kernel throne tracking by touching or sending signal
    log_info "Triggering Manager recognition in KernelSU..."
    ${SUDO_CMD} touch /data/system/packages.list 2>/dev/null || true
fi

echo ""
log_header "Redroid /data Setup Complete!"
echo -e "${GREEN}${BOLD}Status Summary:${NC}"
echo -e "  Redroid Data Dir: ${BOLD}${TARGET_DATA_DIR}${NC}"
echo -e "  Host Mount Point: ${BOLD}/data${NC}"
echo -e "  Manager App UID:  ${BOLD}${EFFECTIVE_UID}${NC}"
echo ""
echo -e "${BOLD}Next Steps:${NC}"
echo -e "  1. Switch to your Redroid window and open (or restart) the ${BOLD}KernelSU-Next Manager${NC} app."
echo -e "  2. The status should now change from 'Not installed' to ${GREEN}${BOLD}'Working'${NC}!"
echo -e "  3. Check dmesg on host (${CYAN}sudo dmesg | grep KernelSU${NC}) to confirm successful crowning."
echo ""
