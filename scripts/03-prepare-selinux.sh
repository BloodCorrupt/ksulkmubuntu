#!/usr/bin/env bash
# ==============================================================================
# 03-prepare-selinux.sh - Download & install missing SELinux headers into kernel build dir
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/00-common.sh"

log_header "Preparing Missing Kernel SELinux Headers"

check_root_or_sudo
ensure_dirs

KERNEL_RELEASE="$(uname -r)"
KERNEL_BUILD_DIR="/lib/modules/${KERNEL_RELEASE}/build"

if [[ ! -d "${KERNEL_BUILD_DIR}" ]]; then
    log_fatal "Kernel build directory ${KERNEL_BUILD_DIR} does not exist. Run 02-install-deps.sh first!"
fi

TARGET_SELINUX_DIR="${KERNEL_BUILD_DIR}/security/selinux"
TARGET_INCLUDE_DIR="${TARGET_SELINUX_DIR}/include"

# Check if already generated
if [[ -f "${TARGET_SELINUX_DIR}/flask.h" && -f "${TARGET_SELINUX_DIR}/av_permissions.h" && -f "${TARGET_INCLUDE_DIR}/objsec.h" ]]; then
    log_success "SELinux headers and genheaders outputs already exist at ${TARGET_SELINUX_DIR}!"
    log_info "No further SELinux header preparation needed."
    exit 0
fi

log_step "Determining matching kernel source version..."
KVER_BASE=$(echo "${KERNEL_RELEASE}" | cut -d'-' -f1) # e.g. 7.0.0 or 7.1.8
KVER_MAJ=$(echo "${KVER_BASE}" | cut -d'.' -f1)       # e.g. 7
KVER_MIN=$(echo "${KVER_BASE}" | cut -d'.' -f2)       # e.g. 0
KVER_PATCH=$(echo "${KVER_BASE}" | cut -d'.' -f3)     # e.g. 0

log_info "Active kernel release: ${KERNEL_RELEASE}"
log_info "Parsed base version:   ${KVER_BASE} (Major: ${KVER_MAJ}, Minor: ${KVER_MIN})"

SRC_DOWNLOAD_DIR="${WORKSPACE_DIR}/kernel_source"
mkdir -p "${SRC_DOWNLOAD_DIR}"
cd "${SRC_DOWNLOAD_DIR}" || exit 1

# Check if we already have security/selinux extracted locally
EXTRACTED_SELINUX=""
if [[ -d "${SRC_DOWNLOAD_DIR}/security/selinux" ]]; then
    EXTRACTED_SELINUX="${SRC_DOWNLOAD_DIR}/security/selinux"
fi

if [[ -z "${EXTRACTED_SELINUX}" ]]; then
    TARBALL=""
    # Candidate URLs to try on cdn.kernel.org
    CANDIDATE_URLS=(
        "${KERNEL_CDN_BASE}/v${KVER_MAJ}.x/linux-${KVER_BASE}.tar.xz"
        "${KERNEL_CDN_BASE}/v${KVER_MAJ}.x/linux-${KVER_MAJ}.${KVER_MIN}.tar.xz"
        "${KERNEL_CDN_BASE}/v${KVER_MAJ}.x/linux-${KVER_BASE}.tar.gz"
    )

    log_step "Attempting to locate kernel source tarball..."
    for url in "${CANDIDATE_URLS[@]}"; do
        log_info "Probing ${url}..."
        if curl --head --silent --fail "${url}" >/dev/null; then
            TARBALL_URL="${url}"
            TARBALL_FILE="$(basename "${url}")"
            log_success "Found matching kernel archive: ${TARBALL_URL}"
            break
        fi
    done

    if [[ -n "${TARBALL_URL}" ]]; then
        if [[ ! -f "${TARBALL_FILE}" ]]; then
            log_step "Downloading ${TARBALL_FILE}..."
            wget --continue --show-progress -O "${TARBALL_FILE}" "${TARBALL_URL}" || \
                curl -fSL -C - -o "${TARBALL_FILE}" "${TARBALL_URL}"
        fi

        log_step "Extracting only 'security/selinux' from ${TARBALL_FILE}..."
        # Extract only security/selinux directory without unpacking entire gigabytes
        tar -xf "${TARBALL_FILE}" --wildcards '*/security/selinux' --strip-components=1 2>/dev/null || \
        tar -xf "${TARBALL_FILE}" --wildcards '*security/selinux*' 2>/dev/null || \
        tar -xf "${TARBALL_FILE}"
    fi

    # Fallback to apt-get source if tarball download failed
    if [[ ! -d "security/selinux" ]]; then
        log_warn "Direct tarball download did not provide security/selinux. Trying 'apt source'..."
        # Ensure deb-src is present or enabled
        if ! grep -rq "deb-src" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
            log_info "Enabling deb-src repositories in Ubuntu..."
            ${SUDO_CMD} sed -i 's/^Types: deb$/Types: deb deb-src/' /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || true
            ${SUDO_CMD} apt-get update -y || true
        fi
        apt-get source --download-only "linux-image-unsigned-${KERNEL_RELEASE}" 2>/dev/null || \
        apt-get source --download-only linux 2>/dev/null || true

        # Find any downloaded linux_*.orig.tar.* or linux_*.tar.*
        APT_TAR=$(find . -maxdepth 1 -name "linux_*.orig.tar.*" -o -name "linux_*.tar.*" | head -n 1)
        if [[ -n "${APT_TAR}" ]]; then
            log_info "Extracting SELinux headers from ${APT_TAR}..."
            tar -xf "${APT_TAR}" --wildcards '*/security/selinux' --strip-components=1 2>/dev/null || \
            tar -xf "${APT_TAR}"
        fi
    fi
fi

# Locate security/selinux in the extraction directory
SELINUX_SRC_DIR=$(find "${SRC_DOWNLOAD_DIR}" -type d -path "*/security/selinux" | head -n 1)

if [[ -z "${SELINUX_SRC_DIR}" || ! -d "${SELINUX_SRC_DIR}" ]]; then
    log_fatal "Could not acquire 'security/selinux' headers. Please ensure you have internet access or supply kernel source!"
fi

log_success "Found SELinux source at: ${SELINUX_SRC_DIR}"

log_step "Installing SELinux headers into ${TARGET_SELINUX_DIR}..."
${SUDO_CMD} mkdir -p "${TARGET_SELINUX_DIR}/genheaders"
${SUDO_CMD} mkdir -p "${TARGET_SELINUX_DIR}/include"
${SUDO_CMD} mkdir -p "${TARGET_SELINUX_DIR}/ss"

# Copy genheaders source
if [[ -d "${SELINUX_SRC_DIR}/genheaders" ]]; then
    ${SUDO_CMD} cp -rf "${SELINUX_SRC_DIR}/genheaders/"* "${TARGET_SELINUX_DIR}/genheaders/"
elif [[ -f "${SELINUX_SRC_DIR}/genheaders.c" ]]; then
    ${SUDO_CMD} cp -f "${SELINUX_SRC_DIR}/genheaders.c" "${TARGET_SELINUX_DIR}/genheaders/"
fi

# Copy includes
${SUDO_CMD} cp -rf "${SELINUX_SRC_DIR}/include/"* "${TARGET_SELINUX_DIR}/include/"

# Copy ss headers
if [[ -d "${SELINUX_SRC_DIR}/ss" ]]; then
    ${SUDO_CMD} cp -rf "${SELINUX_SRC_DIR}/ss/"*.h "${TARGET_SELINUX_DIR}/ss/" 2>/dev/null || true
fi

# Compile genheaders utility
log_step "Compiling genheaders utility..."
GENHEADERS_BIN="${TARGET_SELINUX_DIR}/genheaders/genheaders"
GENHEADERS_C=$(find "${TARGET_SELINUX_DIR}/genheaders" -name "genheaders.c" | head -n 1)

if [[ ! -f "${GENHEADERS_C}" && -f "${TARGET_SELINUX_DIR}/genheaders.c" ]]; then
    GENHEADERS_C="${TARGET_SELINUX_DIR}/genheaders.c"
fi

if [[ -f "${GENHEADERS_C}" ]]; then
    ${SUDO_CMD} gcc -O2 -Wall \
        -I"${TARGET_SELINUX_DIR}/include" \
        -I"${TARGET_SELINUX_DIR}" \
        "${GENHEADERS_C}" \
        -o "${GENHEADERS_BIN}"
    ${SUDO_CMD} chmod +x "${GENHEADERS_BIN}"
fi

if [[ ! -x "${GENHEADERS_BIN}" ]]; then
    log_fatal "Failed to build genheaders binary at ${GENHEADERS_BIN}!"
fi

log_step "Generating flask.h and av_permissions.h..."
cd "${TARGET_SELINUX_DIR}" || exit 1
${SUDO_CMD} "${GENHEADERS_BIN}" flask.h av_permissions.h

# Ensure both paths have flask.h and av_permissions.h to avoid #include search discrepancies
${SUDO_CMD} cp -f flask.h av_permissions.h "${TARGET_INCLUDE_DIR}/"

# Verify required files
MISSING=0
for f in "${TARGET_SELINUX_DIR}/flask.h" "${TARGET_SELINUX_DIR}/av_permissions.h" "${TARGET_INCLUDE_DIR}/flask.h" "${TARGET_INCLUDE_DIR}/objsec.h"; do
    if [[ ! -f "${f}" ]]; then
        log_error "Missing expected file: ${f}"
        MISSING=1
    fi
done

if [[ ${MISSING} -eq 0 ]]; then
    log_success "SELinux headers successfully generated and verified in ${TARGET_SELINUX_DIR}!"
else
    log_fatal "SELinux header generation failed. Missing generated files."
fi
