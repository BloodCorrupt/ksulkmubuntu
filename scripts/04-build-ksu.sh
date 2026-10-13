#!/usr/bin/env bash
# ==============================================================================
# 04-build-ksu.sh - Clone KernelSU / SukiSU and compile out-of-tree LKM (kernelsu.ko)
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/00-common.sh"

VARIANT_NAME="KernelSU-Next"
ACTIVE_REPO="${KSU_GIT_REPO}"
ACTIVE_BRANCH="${KSU_GIT_BRANCH}"
SRC_SUBDIR="KernelSU-Next"

if [[ "${KSU_VARIANT}" == "sukisu" ]]; then
    VARIANT_NAME="SukiSU-Ultra"
    ACTIVE_REPO="${SUKISU_GIT_REPO}"
    ACTIVE_BRANCH="${SUKISU_GIT_BRANCH}"
    SRC_SUBDIR="SukiSU-Ultra"
fi

log_header "Building ${VARIANT_NAME} LKM for x86_64"

ensure_dirs

KERNEL_RELEASE="$(uname -r)"
KERNEL_BUILD_DIR="/lib/modules/${KERNEL_RELEASE}/build"

if [[ ! -d "${KERNEL_BUILD_DIR}" ]]; then
    log_fatal "Kernel build directory ${KERNEL_BUILD_DIR} does not exist!"
fi

KSU_SRC_DIR="${WORKSPACE_DIR}/${SRC_SUBDIR}"

log_step "Cloning/Updating ${VARIANT_NAME} repository (${ACTIVE_BRANCH} branch)..."
if [[ -d "${KSU_SRC_DIR}/.git" ]]; then
    cd "${KSU_SRC_DIR}" || exit 1
    log_info "Fetching latest commits from ${ACTIVE_REPO}..."
    git fetch origin
    git checkout "${ACTIVE_BRANCH}"
    git pull origin "${ACTIVE_BRANCH}"
else
    log_info "Cloning ${ACTIVE_REPO} (${ACTIVE_BRANCH})..."
    git clone --depth 1 -b "${ACTIVE_BRANCH}" "${ACTIVE_REPO}" "${KSU_SRC_DIR}"
fi

cd "${KSU_SRC_DIR}" || exit 1
CURRENT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
log_info "Active ${VARIANT_NAME} commit: ${CURRENT_COMMIT}"

KSU_KERNEL_DIR="${KSU_SRC_DIR}/kernel"
if [[ ! -d "${KSU_KERNEL_DIR}" ]]; then
    log_fatal "Expected kernel module directory ${KSU_KERNEL_DIR} not found in repository!"
fi

# Apply Container / Redroid Compatibility Patch
log_step "Checking Container / Redroid Compatibility..."
THRONE_TRACKER="${KSU_KERNEL_DIR}/manager/throne_tracker.c"
MANAGER_IDENTITY="${KSU_KERNEL_DIR}/manager/manager_identity.h"

if [[ -f "${THRONE_TRACKER}" && -f "${MANAGER_IDENTITY}" ]]; then
    if ! grep -q "ksu_container_manager_uid" "${THRONE_TRACKER}"; then
        log_info "Applying container manager parameter patch to throne_tracker.c..."
        sed -i '/uid_t ksu_manager_appid = KSU_INVALID_APPID;/a \
int ksu_container_manager_uid = -1;\
module_param_named(manager_uid, ksu_container_manager_uid, int, 0644);\
MODULE_PARM_DESC(manager_uid, "Override or container fallback manager UID");' "${THRONE_TRACKER}"
    fi

    if ! grep -q "ksu_container_manager_uid" "${MANAGER_IDENTITY}"; then
        log_info "Applying container manager resolution patch to manager_identity.h..."
        # Add extern declaration before functions
        sed -i '/extern uid_t ksu_manager_appid;/a \
extern int ksu_container_manager_uid;' "${MANAGER_IDENTITY}"

        # Patch is_manager() to check ksu_container_manager_uid
        sed -i 's/return unlikely(ksu_manager_appid == current_uid().val % KSU_PER_USER_RANGE);/if (ksu_container_manager_uid >= 0 && (current_uid().val % KSU_PER_USER_RANGE) == (ksu_container_manager_uid % KSU_PER_USER_RANGE)) return true; return unlikely(ksu_manager_appid == current_uid().val % KSU_PER_USER_RANGE);/' "${MANAGER_IDENTITY}"

        # Patch is_uid_manager()
        sed -i 's/return unlikely(ksu_manager_appid == uid % KSU_PER_USER_RANGE);/if (ksu_container_manager_uid >= 0 && (uid % KSU_PER_USER_RANGE) == (ksu_container_manager_uid % KSU_PER_USER_RANGE)) return true; return unlikely(ksu_manager_appid == uid % KSU_PER_USER_RANGE);/' "${MANAGER_IDENTITY}"

        # Patch ksu_is_manager_appid_valid()
        sed -i 's/return ksu_manager_appid != KSU_INVALID_APPID;/if (ksu_container_manager_uid >= 0) return true; return ksu_manager_appid != KSU_INVALID_APPID;/' "${MANAGER_IDENTITY}"
    fi
    log_success "Container compatibility verified (/sys/module/kernelsu/parameters/manager_uid enabled)."
fi

# Clean previous build artifacts
log_step "Cleaning old module objects..."
make -C "${KERNEL_BUILD_DIR}" M="${KSU_KERNEL_DIR}" clean 2>/dev/null || true

log_step "Compiling ${VARIANT_NAME} LKM..."
echo -e "${CYAN}Flags:${NC}"
echo -e "  CONFIG_KSU=m"
echo -e "  KBUILD_MODPOST_WARN=1"
echo -e "  CONFIG_KSU_X86_PATCH_SYSCALL_DISPATCHER=y"
echo -e "  Jobs: $(nproc)\n"

make -j"$(nproc)" -C "${KERNEL_BUILD_DIR}" \
    M="${KSU_KERNEL_DIR}" \
    CONFIG_KSU=m \
    KBUILD_MODPOST_WARN=1 \
    CONFIG_KSU_X86_PATCH_SYSCALL_DISPATCHER=y \
    modules

COMPILED_KO="${KSU_KERNEL_DIR}/kernelsu.ko"

if [[ ! -f "${COMPILED_KO}" ]]; then
    log_fatal "Compilation finished but '${COMPILED_KO}' was not created!"
fi

# Copy artifact to output directory
cp -f "${COMPILED_KO}" "${OUTPUT_DIR}/kernelsu.ko"

log_success "Successfully compiled kernelsu.ko (${VARIANT_NAME})!"
echo -e "\n${BOLD}Module Details:${NC}"
echo -e "  File:    ${BOLD}${OUTPUT_DIR}/kernelsu.ko${NC}"
echo -e "  Variant: ${BOLD}${VARIANT_NAME}${NC}"
echo -e "  Size:    $(du -h "${OUTPUT_DIR}/kernelsu.ko" | cut -f1)"
echo -e "  SHA256:  $(sha256sum "${OUTPUT_DIR}/kernelsu.ko" | cut -d' ' -f1)"

if command -v modinfo &>/dev/null; then
    echo ""
    log_info "Inspecting Module Info:"
    modinfo "${OUTPUT_DIR}/kernelsu.ko" | grep -E "^(filename|version|description|author|vermagic):" || true
fi
