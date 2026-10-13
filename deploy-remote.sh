#!/usr/bin/env bash
# ==============================================================================
# deploy-remote.sh - Deploy suite to remote Ubuntu host over SSH / SCP
# ==============================================================================

set -euo pipefail

REMOTE_HOST="${1:-10.13.37.183}"
REMOTE_USER="${2:-bloodtek}"
REMOTE_PORT="${3:-22}"
REMOTE_PATH="${4:-~/ksu-x64-builder}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Deploying KernelSU Suite to ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH} ==="

ssh -p "${REMOTE_PORT}" "${REMOTE_USER}@${REMOTE_HOST}" "mkdir -p ${REMOTE_PATH}"

scp -P "${REMOTE_PORT}" -r \
    "${SCRIPT_DIR}/config.env" \
    "${SCRIPT_DIR}/ksu-suite.sh" \
    "${SCRIPT_DIR}/scripts" \
    "${SCRIPT_DIR}/src" \
    "${SCRIPT_DIR}/systemd" \
    "${SCRIPT_DIR}/README.md" \
    "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_PATH}/"

ssh -p "${REMOTE_PORT}" "${REMOTE_USER}@${REMOTE_HOST}" "chmod +x ${REMOTE_PATH}/ksu-suite.sh ${REMOTE_PATH}/scripts/*.sh"

echo "[+] Files uploaded and permissions set!"
echo "Run on remote: ssh ${REMOTE_USER}@${REMOTE_HOST} 'cd ${REMOTE_PATH} && ./ksu-suite.sh'"
