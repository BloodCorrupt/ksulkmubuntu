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
    git checkout -f "${ACTIVE_BRANCH}"
    git pull origin "${ACTIVE_BRANCH}"
else
    log_info "Cloning ${ACTIVE_REPO} (${ACTIVE_BRANCH})..."
    git clone --depth 1 -b "${ACTIVE_BRANCH}" "${ACTIVE_REPO}" "${KSU_SRC_DIR}"
fi

cd "${KSU_SRC_DIR}" || exit 1
CURRENT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
log_info "Active ${VARIANT_NAME} commit: ${CURRENT_COMMIT}"

# Reset any broken/previous patches in working tree
log_info "Ensuring clean source tree..."
git checkout -f -- . 2>/dev/null || true
git clean -fd 2>/dev/null || true

KSU_KERNEL_DIR="${KSU_SRC_DIR}/kernel"
if [[ ! -d "${KSU_KERNEL_DIR}" ]]; then
    log_fatal "Expected kernel module directory ${KSU_KERNEL_DIR} not found in repository!"
fi

# Apply Container / Redroid Compatibility Patch
log_step "Applying Container / Redroid Compatibility Patch..."
THRONE_TRACKER="${KSU_KERNEL_DIR}/manager/throne_tracker.c"
MANAGER_IDENTITY="${KSU_KERNEL_DIR}/manager/manager_identity.h"

if [[ -f "${THRONE_TRACKER}" && -f "${MANAGER_IDENTITY}" ]]; then
    python3 - "${THRONE_TRACKER}" "${MANAGER_IDENTITY}" << 'EOF'
import sys, re

tt_path = sys.argv[1]
mi_path = sys.argv[2]

# 1. Patch throne_tracker.c
with open(tt_path, "r") as f:
    tt_content = f.read()

if "ksu_container_manager_uid" not in tt_content:
    tt_patch = """uid_t ksu_manager_appid = KSU_INVALID_APPID;
int ksu_container_manager_uid = -1;
module_param_named(manager_uid, ksu_container_manager_uid, int, 0644);
MODULE_PARM_DESC(manager_uid, "Override or container fallback manager UID");"""
    tt_content = tt_content.replace("uid_t ksu_manager_appid = KSU_INVALID_APPID;", tt_patch)
    with open(tt_path, "w") as f:
        f.write(tt_content)

# 2. Patch manager_identity.h
with open(mi_path, "r") as f:
    mi_content = f.read()

if "ksu_container_manager_uid" not in mi_content:
    replacement = """extern uid_t ksu_manager_appid; // DO NOT DIRECT USE
extern int ksu_container_manager_uid;

static inline bool ksu_is_manager_appid_valid()
{
    if (ksu_container_manager_uid >= 0)
        return true;
    return ksu_manager_appid != KSU_INVALID_APPID;
}

static inline bool is_manager()
{
    if (ksu_container_manager_uid >= 0 &&
        (current_uid().val % KSU_PER_USER_RANGE) == (ksu_container_manager_uid % KSU_PER_USER_RANGE))
        return true;
    return unlikely(ksu_manager_appid == current_uid().val % KSU_PER_USER_RANGE);
}

static inline bool is_uid_manager(uid_t uid)
{
    if (ksu_container_manager_uid >= 0 &&
        (uid % KSU_PER_USER_RANGE) == (ksu_container_manager_uid % KSU_PER_USER_RANGE))
        return true;
    return unlikely(ksu_manager_appid == uid % KSU_PER_USER_RANGE);
}

static inline uid_t ksu_get_manager_appid()
{
    if (ksu_container_manager_uid >= 0 && ksu_manager_appid == KSU_INVALID_APPID)
        return ksu_container_manager_uid % KSU_PER_USER_RANGE;
    return ksu_manager_appid;
}"""
    pattern = r"extern uid_t ksu_manager_appid; // DO NOT DIRECT USE.*?return ksu_manager_appid;\s*\}"
    mi_content = re.sub(pattern, replacement, mi_content, flags=re.DOTALL)
    with open(mi_path, "w") as f:
        f.write(mi_content)
EOF
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
