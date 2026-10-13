#!/usr/bin/env bash
# ==============================================================================
# 04-build-ksu.sh - Clone Official KernelSU and compile out-of-tree LKM (kernelsu.ko)
# Repository: https://github.com/tiann/KernelSU.git
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/00-common.sh"

log_header "Building Official KernelSU (tiann/KernelSU) for x86_64"

ensure_dirs

KERNEL_RELEASE="$(uname -r)"
KERNEL_BUILD_DIR="/lib/modules/${KERNEL_RELEASE}/build"

if [[ ! -d "${KERNEL_BUILD_DIR}" ]]; then
    log_fatal "Kernel build directory ${KERNEL_BUILD_DIR} does not exist!"
fi

KSU_SRC_DIR="${WORKSPACE_DIR}/KernelSU"

log_step "Cloning/Updating official KernelSU repository (${KSU_GIT_BRANCH})..."
if [[ -d "${KSU_SRC_DIR}/.git" ]]; then
    cd "${KSU_SRC_DIR}" || exit 1
    log_info "Fetching latest commits from ${KSU_GIT_REPO}..."
    git remote set-url origin "${KSU_GIT_REPO}"
    git fetch origin
    git checkout -f "${KSU_GIT_BRANCH}"
    git pull origin "${KSU_GIT_BRANCH}" 2>/dev/null || true
    git clean -fd
else
    log_info "Cloning ${KSU_GIT_REPO} (${KSU_GIT_BRANCH})..."
    git clone --depth 1 -b "${KSU_GIT_BRANCH}" "${KSU_GIT_REPO}" "${KSU_SRC_DIR}"
fi

cd "${KSU_SRC_DIR}" || exit 1
CURRENT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
log_info "Active KernelSU commit: ${CURRENT_COMMIT}"

# Ensure clean upstream state before compiling
git checkout -f -- . 2>/dev/null || true
git clean -fd 2>/dev/null || true

KSU_KERNEL_DIR="${KSU_SRC_DIR}/kernel"
if [[ ! -d "${KSU_KERNEL_DIR}" ]]; then
    log_fatal "Expected kernel module directory ${KSU_KERNEL_DIR} not found in repository!"
fi

# Apply Container Auto-Crowning Patch (enables manager without host /data mount)
log_step "Enabling Container Auto-Crowning for Manager..."
MANAGER_IDENTITY="${KSU_KERNEL_DIR}/manager/manager_identity.h"

if [[ -f "${MANAGER_IDENTITY}" ]]; then
    python3 - "${MANAGER_IDENTITY}" << 'EOF'
import sys

mi_path = sys.argv[1]
with open(mi_path, "r") as f:
    content = f.read()

if "auto-crowning" not in content:
    old_block = """static inline bool is_manager()
{
    return unlikely(ksu_manager_appid == current_uid().val % KSU_PER_USER_RANGE);
}"""

    new_block = """static inline bool is_manager()
{
    if (unlikely(ksu_manager_appid == KSU_INVALID_APPID)) {
        uid_t appid = current_uid().val % KSU_PER_USER_RANGE;
        if (appid >= 10000 && appid < 20000) {
            pr_info("KernelSU: container auto-crowning manager appid %d\\n", appid);
            ksu_manager_appid = appid;
            return true;
        }
    }
    return unlikely(ksu_manager_appid == current_uid().val % KSU_PER_USER_RANGE);
}"""

    if old_block in content:
        content = content.replace(old_block, new_block, 1)
        with open(mi_path, "w") as f:
            f.write(content)
EOF
    log_success "Container auto-crowning enabled (manager will be recognized automatically in Redroid)."
fi

# Clean previous build artifacts
log_step "Cleaning old module objects..."
make -C "${KERNEL_BUILD_DIR}" M="${KSU_KERNEL_DIR}" clean 2>/dev/null || true

log_step "Compiling Official KernelSU LKM..."
echo -e "${CYAN}Configuration:${NC}"
echo -e "  Repository: ${KSU_GIT_REPO}"
echo -e "  Branch:     ${KSU_GIT_BRANCH}"
echo -e "  CONFIG_KSU=m"
echo -e "  KBUILD_MODPOST_WARN=1"
echo -e "  CONFIG_KSU_X86_PATCH_SYSCALL_DISPATCHER=y"
echo -e "  Jobs:       $(nproc)\n"

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

log_success "Successfully compiled official kernelsu.ko!"
echo -e "\n${BOLD}Module Details:${NC}"
echo -e "  File:   ${BOLD}${OUTPUT_DIR}/kernelsu.ko${NC}"
echo -e "  Size:   $(du -h "${OUTPUT_DIR}/kernelsu.ko" | cut -f1)"
echo -e "  SHA256: $(sha256sum "${OUTPUT_DIR}/kernelsu.ko" | cut -d' ' -f1)"

if command -v modinfo &>/dev/null; then
    echo ""
    log_info "Inspecting Module Info:"
    modinfo "${OUTPUT_DIR}/kernelsu.ko" | grep -E "^(filename|version|description|author|vermagic):" || true
fi
