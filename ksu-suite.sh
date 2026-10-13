#!/usr/bin/env bash
# ==============================================================================
# ksu-suite.sh - Master CLI and Interactive Suite for KernelSU on Ubuntu
# Target System: Ubuntu 26.04 LTS (x86_64), Linux Kernel 7.x / 6.x
# Supported Backends: KernelSU-Next (dev), SukiSU-Ultra (main)
# ==============================================================================

set -eo pipefail

SUITE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SUITE_DIR}/scripts/00-common.sh"

run_all_pipeline() {
    log_header "Starting Full Automated KernelSU Build & Load Pipeline (${KSU_VARIANT})"
    START_TIME=$(date +%s)

    bash "${SCRIPTS_DIR}/01-check-env.sh"
    bash "${SCRIPTS_DIR}/02-install-deps.sh"
    bash "${SCRIPTS_DIR}/03-prepare-selinux.sh"
    bash "${SCRIPTS_DIR}/04-build-ksu.sh"
    bash "${SCRIPTS_DIR}/05-fetch-lkmloader.sh"
    bash "${SCRIPTS_DIR}/06-load-module.sh"

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
        bash "${SCRIPTS_DIR}/07-systemd-service.sh"
    fi
}

toggle_variant() {
    if [[ "${KSU_VARIANT}" == "sukisu" ]]; then
        sed -i 's/^KSU_VARIANT=.*/KSU_VARIANT="ksu-next"/' "${ROOT_DIR}/config.env"
        KSU_VARIANT="ksu-next"
        log_success "Switched active variant to: KernelSU-Next"
    else
        sed -i 's/^KSU_VARIANT=.*/KSU_VARIANT="sukisu"/' "${ROOT_DIR}/config.env"
        KSU_VARIANT="sukisu"
        log_success "Switched active variant to: SukiSU-Ultra"
    fi
}

show_menu() {
    while true; do
        clear 2>/dev/null || true
        # Reload config in case toggled
        if [[ -f "${ROOT_DIR}/config.env" ]]; then
            # shellcheck source=/dev/null
            source "${ROOT_DIR}/config.env"
        fi

        CURRENT_NAME="KernelSU-Next"
        if [[ "${KSU_VARIANT}" == "sukisu" ]]; then
            CURRENT_NAME="SukiSU-Ultra"
        fi

        echo -e "${BOLD}${CYAN}╔═════════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BOLD}${CYAN}║            KernelSU x86_64 Builder Suite - Ubuntu 26.04 LTS             ║${NC}"
        echo -e "${BOLD}${CYAN}╚═════════════════════════════════════════════════════════════════════════╝${NC}"
        echo -e "  Active Backend: ${BOLD}${GREEN}${CURRENT_NAME}${NC} (KSU_VARIANT=${KSU_VARIANT})"
        echo -e "  Active Kernel:  ${BOLD}$(uname -r)${NC} | Arch: ${BOLD}$(uname -m)${NC}"
        echo -e "  Directory:      ${ROOT_DIR}\n"

        echo -e "  ${BOLD}${GREEN}[1]${NC} ${BOLD}Full Automated Pipeline${NC} (Check -> Deps -> SELinux -> Build -> Load)"
        echo -e "  ${BOLD}${CYAN}[2]${NC} Check Environment & Secure Boot Status"
        echo -e "  ${BOLD}${CYAN}[3]${NC} Install Compilation Dependencies & Kernel Headers"
        echo -e "  ${BOLD}${CYAN}[4]${NC} Download & Prepare Missing SELinux Headers (genheaders)"
        echo -e "  ${BOLD}${CYAN}[5]${NC} Clone & Build ${CURRENT_NAME} LKM (kernelsu.ko)"
        echo -e "  ${BOLD}${CYAN}[6]${NC} Fetch/Compile LKM Loader (maxsteeel/lkmloader)"
        echo -e "  ${BOLD}${CYAN}[7]${NC} Load KernelSU Module via lkmloader"
        echo -e "  ${BOLD}${MAGENTA}[8]${NC} ${BOLD}Redroid Helper:${NC} Link Container /data & Authorize Manager"
        echo -e "  ${BOLD}${CYAN}[9]${NC} Configure Persistent Systemd Boot Service"
        echo -e "  ${BOLD}${YELLOW}[T]${NC} Toggle Backend Variant (${BOLD}KernelSU-Next${NC} <-> ${BOLD}SukiSU-Ultra${NC})"
        echo -e "  ${BOLD}${YELLOW}[C]${NC} Clean Build Workspace"
        echo -e "  ${BOLD}${RED}[0]${NC} Exit\n"

        read -rp "Select an option [0-9, T, C]: " OPTION
        echo ""

        case "${OPTION}" in
            1) run_all_pipeline ;;
            2) bash "${SCRIPTS_DIR}/01-check-env.sh" ;;
            3) bash "${SCRIPTS_DIR}/02-install-deps.sh" ;;
            4) bash "${SCRIPTS_DIR}/03-prepare-selinux.sh" ;;
            5) bash "${SCRIPTS_DIR}/04-build-ksu.sh" ;;
            6) bash "${SCRIPTS_DIR}/05-fetch-lkmloader.sh" ;;
            7) bash "${SCRIPTS_DIR}/06-load-module.sh" ;;
            8) bash "${SCRIPTS_DIR}/09-setup-redroid.sh" ;;
            9) bash "${SCRIPTS_DIR}/07-systemd-service.sh" ;;
            [Tt]) toggle_variant ;;
            [Cc]) bash "${SCRIPTS_DIR}/08-clean.sh" ;;
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
    echo "  -b, --build       Clone selected backend and compile kernelsu.ko"
    echo "  -l, --loader      Fetch or compile maxsteeel/lkmloader binary"
    echo "  -m, --load        Load kernelsu.ko into running kernel with lkmloader"
    echo "  -r, --redroid     Run Redroid /data host bind-mount & crown manager"
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
        -c|--check)       bash "${SCRIPTS_DIR}/01-check-env.sh" ;;
        -d|--deps)        bash "${SCRIPTS_DIR}/02-install-deps.sh" ;;
        -s|--selinux)     bash "${SCRIPTS_DIR}/03-prepare-selinux.sh" ;;
        -b|--build)       bash "${SCRIPTS_DIR}/04-build-ksu.sh" ;;
        -l|--loader)      bash "${SCRIPTS_DIR}/05-fetch-lkmloader.sh" ;;
        -m|--load)        bash "${SCRIPTS_DIR}/06-load-module.sh" ;;
        -r|--redroid)     bash "${SCRIPTS_DIR}/09-setup-redroid.sh" ;;
        --service)        bash "${SCRIPTS_DIR}/07-systemd-service.sh" ;;
        --clean)          bash "${SCRIPTS_DIR}/08-clean.sh" ;;
        -h|--help)        print_help ;;
        *)
            log_error "Unknown option: $1"
            print_help
            exit 1
            ;;
    esac
fi
