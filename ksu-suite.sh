#!/usr/bin/env bash
# ==============================================================================
# ksu-suite.sh - Master CLI and Interactive Suite for KernelSU-Next on Ubuntu
# Target System: Ubuntu 26.04 LTS (x86_64), Linux Kernel 7.x / 6.x
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/scripts/00-common.sh"

run_all_pipeline() {
    log_header "Starting Full Automated KernelSU Build & Load Pipeline"
    START_TIME=$(date +%s)

    bash "${SCRIPT_DIR}/scripts/01-check-env.sh"
    bash "${SCRIPT_DIR}/scripts/02-install-deps.sh"
    bash "${SCRIPT_DIR}/scripts/03-prepare-selinux.sh"
    bash "${SCRIPT_DIR}/scripts/04-build-ksu.sh"
    bash "${SCRIPT_DIR}/scripts/05-fetch-lkmloader.sh"
    bash "${SCRIPT_DIR}/scripts/06-load-module.sh"

    END_TIME=$(date +%s)
    DIFF=$((END_TIME - START_TIME))

    echo ""
    log_header "Pipeline Completed Successfully in ${DIFF}s!"
    echo -e "${GREEN}${BOLD}[✓] Output Artifacts:${NC}"
    echo -e "    Module: ${BOLD}${OUTPUT_DIR}/kernelsu.ko${NC}"
    echo -e "    Loader: ${BOLD}${OUTPUT_DIR}/lkmloader-x86_64${NC}"
    echo ""

    read -rp "Would you like to install the persistent systemd service now? [y/N]: " INSTALL_SRV
    if [[ "${INSTALL_SRV}" =~ ^[Yy]$ ]]; then
        bash "${SCRIPT_DIR}/scripts/07-systemd-service.sh"
    fi
}

show_menu() {
    while true; do
        clear 2>/dev/null || true
        echo -e "${BOLD}${CYAN}╔═════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BOLD}${CYAN}║         KernelSU-Next x86_64 Builder Suite - Ubuntu 26.04 LTS           ║${NC}"
        echo -e "${BOLD}${CYAN}╚═════════════════════════════════════════════════════════════════════════╝${NC}"
        echo -e "  Active Kernel: ${BOLD}$(uname -r)${NC} | Arch: ${BOLD}$(uname -m)${NC}"
        echo -e "  Directory:     ${SCRIPT_DIR}\n"

        echo -e "  ${BOLD}${GREEN}[1]${NC} ${BOLD}Full Automated Pipeline${NC} (Check -> Deps -> SELinux -> Build -> Load)"
        echo -e "  ${BOLD}${CYAN}[2]${NC} Check Environment & Secure Boot Status"
        echo -e "  ${BOLD}${CYAN}[3]${NC} Install Compilation Dependencies & Kernel Headers"
        echo -e "  ${BOLD}${CYAN}[4]${NC} Download & Prepare Missing SELinux Headers (genheaders)"
        echo -e "  ${BOLD}${CYAN}[5]${NC} Clone & Build KernelSU-Next LKM (kernelsu.ko)"
        echo -e "  ${BOLD}${CYAN}[6]${NC} Fetch/Compile LKM Loader (maxsteeel/lkmloader)"
        echo -e "  ${BOLD}${CYAN}[7]${NC} Load KernelSU Module via lkmloader"
        echo -e "  ${BOLD}${CYAN}[8]${NC} Configure Persistent Systemd Boot Service"
        echo -e "  ${BOLD}${YELLOW}[9]${NC} Clean Build Workspace"
        echo -e "  ${BOLD}${RED}[0]${NC} Exit\n"

        read -rp "Select an option [0-9]: " OPTION
        echo ""

        case "${OPTION}" in
            1) run_all_pipeline ;;
            2) bash "${SCRIPT_DIR}/scripts/01-check-env.sh" ;;
            3) bash "${SCRIPT_DIR}/scripts/02-install-deps.sh" ;;
            4) bash "${SCRIPT_DIR}/scripts/03-prepare-selinux.sh" ;;
            5) bash "${SCRIPT_DIR}/scripts/04-build-ksu.sh" ;;
            6) bash "${SCRIPT_DIR}/scripts/05-fetch-lkmloader.sh" ;;
            7) bash "${SCRIPT_DIR}/scripts/06-load-module.sh" ;;
            8) bash "${SCRIPT_DIR}/scripts/07-systemd-service.sh" ;;
            9) bash "${SCRIPT_DIR}/scripts/08-clean.sh" ;;
            0) echo -e "${CYAN}Exiting. Have a nice day!${NC}"; exit 0 ;;
            *) log_warn "Invalid option selected: ${OPTION}" ;;
        esac

        echo ""
        read -rp "Press Enter to return to menu..."
    done
}

print_help() {
    echo -e "${BOLD}Usage:${NC} $0 [options]"
    echo ""
    echo "Options:"
    echo "  -a, --all         Execute complete automated pipeline (Check -> Build -> Load)"
    echo "  -c, --check       Run environment and Secure Boot pre-flight checks"
    echo "  -d, --deps        Install required build dependencies and linux-headers"
    echo "  -s, --selinux     Download kernel source and generate missing SELinux headers"
    echo "  -b, --build       Clone KernelSU-Next and compile kernelsu.ko"
    echo "  -l, --loader      Fetch or compile maxsteeel/lkmloader binary"
    echo "  -m, --load        Load kernelsu.ko into running kernel with lkmloader"
    echo "      --service     Install and activate persistent systemd boot service"
    echo "      --clean       Remove temporary build workspace"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "Running with no arguments launches the interactive console menu."
}

# CLI Argument parsing
if [[ $# -eq 0 ]]; then
    show_menu
else
    case "$1" in
        -a|--all)         run_all_pipeline ;;
        -c|--check)       bash "${SCRIPT_DIR}/scripts/01-check-env.sh" ;;
        -d|--deps)        bash "${SCRIPT_DIR}/scripts/02-install-deps.sh" ;;
        -s|--selinux)     bash "${SCRIPT_DIR}/scripts/03-prepare-selinux.sh" ;;
        -b|--build)       bash "${SCRIPT_DIR}/scripts/04-build-ksu.sh" ;;
        -l|--loader)      bash "${SCRIPT_DIR}/scripts/05-fetch-lkmloader.sh" ;;
        -m|--load)        bash "${SCRIPT_DIR}/scripts/06-load-module.sh" ;;
        --service)        bash "${SCRIPT_DIR}/scripts/07-systemd-service.sh" ;;
        --clean)          bash "${SCRIPT_DIR}/scripts/08-clean.sh" ;;
        -h|--help)        print_help ;;
        *)
            log_error "Unknown option: $1"
            print_help
            exit 1
            ;;
    esac
fi
