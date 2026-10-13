#!/usr/bin/env bash
# ==============================================================================
# 05-fetch-lkmloader.sh - Obtain or compile maxsteeel/lkmloader for x86_64
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/00-common.sh"

log_header "Obtaining LKM Loader (maxsteeel/lkmloader)"

ensure_dirs

TARGET_BIN="${OUTPUT_DIR}/lkmloader-x86_64"

# Check if already acquired and working
if [[ -x "${TARGET_BIN}" ]]; then
    CALC_HASH=$(sha256sum "${TARGET_BIN}" | cut -d' ' -f1)
    if [[ "${CALC_HASH}" == "${LKMLOADER_SHA256}" ]]; then
        log_success "lkmloader-x86_64 binary already exists and matches expected SHA256!"
        exit 0
    fi
fi

DOWNLOAD_SUCCESS=0

log_step "Attempting download of official release v1.0.0 from GitHub..."
log_info "URL: ${LKMLOADER_RELEASE_URL}"

if curl -fSL -o "${TARGET_BIN}.tmp" "${LKMLOADER_RELEASE_URL}" 2>/dev/null || \
   wget -q -O "${TARGET_BIN}.tmp" "${LKMLOADER_RELEASE_URL}" 2>/dev/null; then
    
    DOWNLOAD_HASH=$(sha256sum "${TARGET_BIN}.tmp" | cut -d' ' -f1)
    if [[ "${DOWNLOAD_HASH}" == "${LKMLOADER_SHA256}" ]]; then
        mv "${TARGET_BIN}.tmp" "${TARGET_BIN}"
        chmod +x "${TARGET_BIN}"
        DOWNLOAD_SUCCESS=1
        log_success "Downloaded verified lkmloader-x86_64 release binary!"
    else
        log_warn "Downloaded binary SHA256 mismatch: ${DOWNLOAD_HASH} vs expected ${LKMLOADER_SHA256}."
        mv "${TARGET_BIN}.tmp" "${TARGET_BIN}"
        chmod +x "${TARGET_BIN}"
        DOWNLOAD_SUCCESS=1
    fi
fi

# Fallback: Compile from bundled source
if [[ ${DOWNLOAD_SUCCESS} -ne 1 || ! -x "${TARGET_BIN}" ]]; then
    log_warn "Download failed or skipped. Compiling lkmloader from bundled source..."
    SRC_FILE="${ROOT_DIR}/src/lkmloader.c"
    if [[ ! -f "${SRC_FILE}" ]]; then
        log_fatal "Bundled source ${SRC_FILE} is missing!"
    fi

    log_info "Compiling ${SRC_FILE} with GCC..."
    if gcc -O2 -static "${SRC_FILE}" -o "${TARGET_BIN}" 2>/dev/null; then
        chmod +x "${TARGET_BIN}"
        log_success "Compiled static lkmloader-x86_64 successfully!"
    elif gcc -O2 "${SRC_FILE}" -o "${TARGET_BIN}"; then
        chmod +x "${TARGET_BIN}"
        log_success "Compiled dynamic lkmloader-x86_64 successfully!"
    else
        log_fatal "Failed to compile lkmloader-x86_64!"
    fi
fi

# Quick test execution
TEST_OUTPUT=$("${TARGET_BIN}" 2>&1 || true)
if echo "${TEST_OUTPUT}" | grep -q "Usage:"; then
    log_success "lkmloader-x86_64 is operational!"
    echo -e "  Location: ${BOLD}${TARGET_BIN}${NC}"
    echo -e "  SHA256:   $(sha256sum "${TARGET_BIN}" | cut -d' ' -f1)"
else
    log_warn "lkmloader output unexpected: ${TEST_OUTPUT}"
fi
