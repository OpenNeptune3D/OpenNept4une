#!/bin/bash

# Path to the script and other resources
SCRIPT="${HOME}/OpenNept4une/OpenNept4une.sh"
DISPLAY_SERVICE_INSTALLER="${HOME}/display_connector/display-service-installer.sh"
MCU_RPI_INSTALLER="${HOME}/OpenNept4une/img-config/rpi-mcu-install.sh"
USB_STORAGE_AUTOMOUNT="${HOME}/OpenNept4une/img-config/usb-storage-automount.sh"
ANDROID_RULE_INSTALLER="${HOME}/OpenNept4une/img-config/adb-automount.sh"
UPDATED_DISPLAY_FIRMWARE_INSTALLER="${HOME}/display_firmware/screen-firmware.sh"
WEBCAM_SETUP_INSTALLER="${HOME}/OpenNept4une/img-config/webcam-setup.sh"
BASE_IMAGE_INSTALLER="${HOME}/OpenNept4une/img-config/base_image_configuration.sh"
SSH_KEY_INSTALLER="${HOME}/OpenNept4une/img-config/update-ssh-keys.sh"

FLAG_FILE="/boot/.OpenNept4une.txt"
MODEL_FROM_FLAG=$(grep -E '^N4|^n4' "$FLAG_FILE" 2>/dev/null)
KERNEL_FROM_FLAG=$(grep 'Linux' "$FLAG_FILE" 2>/dev/null | awk '{split($3,a,"-"); print a[1]}')

OPENNEPT4UNE_REPO="https://github.com/OpenNeptune3D/OpenNept4une.git"
OPENNEPT4UNE_DIR="${HOME}/OpenNept4une"
DISPLAY_CONNECTOR_REPO="https://github.com/OpenNeptune3D/display_connector.git"
DISPLAY_CONNECTOR_DIR="${HOME}/display_connector"
DISPLAY_FIRMWARE_REPO="https://github.com/OpenNeptune3D/display_firmware.git"
DISPLAY_FIRMWARE_DIR="${HOME}/display_firmware"

current_branch=""

# Command line arguments
model_key=""
motor_current=""
pcb_version=""
toolhead_variant=""
auto_yes="false"

# ASCII art for OpenNept4une
OPENNEPT4UNE_ART=$(cat <<'EOF'
  ____                _  __         __  ____
 / __ \___  ___ ___  / |/ /__ ___  / /_/ / /__ _____  ___
/ /_/ / _ \/ -_) _ \/    / -_) _ \/ __/_  _/ // / _ \/ -_)
\____/ .__/\__/_//_/_/|_/\__/ .__/\__/ /_/ \_,_/_//_/\__/
    /_/                    /_/

EOF
)

R=$'\e[1;91m'    # Red ${R}
G=$'\e[1;92m'    # Green ${G}
Y=$'\e[1;93m'    # Yellow ${Y}
M=$'\e[1;95m'    # Magenta ${M}
C=$'\e[96m'      # Cyan ${C}
NC=$'\e[0m'      # No Color ${NC}

# Function libraries. All are sourced up front so a self-update (git pull) mid-run
# keeps this process on one consistent version until it re-execs.
LIB_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib"
# shellcheck source=lib/common.sh
source "$LIB_DIR/common.sh" || { printf '%s\n' "Missing $LIB_DIR/common.sh" >&2; exit 1; }
# shellcheck source=lib/fixes.sh
source "$LIB_DIR/fixes.sh" || { printf '%s\n' "Missing $LIB_DIR/fixes.sh" >&2; exit 1; }
# shellcheck source=lib/moonraker.sh
source "$LIB_DIR/moonraker.sh" || { printf '%s\n' "Missing $LIB_DIR/moonraker.sh" >&2; exit 1; }
# shellcheck source=lib/repo_update.sh
source "$LIB_DIR/repo_update.sh" || { printf '%s\n' "Missing $LIB_DIR/repo_update.sh" >&2; exit 1; }
# shellcheck source=lib/display.sh
source "$LIB_DIR/display.sh" || { printf '%s\n' "Missing $LIB_DIR/display.sh" >&2; exit 1; }
# shellcheck source=lib/printer_cfg.sh
source "$LIB_DIR/printer_cfg.sh" || { printf '%s\n' "Missing $LIB_DIR/printer_cfg.sh" >&2; exit 1; }
# shellcheck source=lib/configs.sh
source "$LIB_DIR/configs.sh" || { printf '%s\n' "Missing $LIB_DIR/configs.sh" >&2; exit 1; }
# shellcheck source=lib/menus.sh
source "$LIB_DIR/menus.sh" || { printf '%s\n' "Missing $LIB_DIR/menus.sh" >&2; exit 1; }

# Parse Command-Line Arguments
if ! TEMP=$(getopt -o yh --long yes,help,printer_model:,motor_current:,pcb_version:,toolhead: -n 'OpenNept4une.sh' -- "$@"); then
    printf '%b\n' "${R}Failed to parse options.${NC}" >&2
    exit 1
fi

eval set -- "$TEMP"

while true; do
    case "$1" in
        --printer_model) model_key="$2"; shift 2 ;;
        --motor_current) motor_current="$2"; shift 2 ;;
        --pcb_version) pcb_version="$2"; shift 2 ;;
        --toolhead) toolhead_variant="$2"; shift 2 ;;
        -y|--yes) auto_yes="true"; shift ;;
        -h|--help) print_help; exit 0 ;;
        --) shift; break ;;
        *) printf '%b\n' "${R}Invalid option: $1 ${NC}"; exit 1 ;;
    esac
done

if [[ -n "$toolhead_variant" && "$toolhead_variant" != "ribbon" && "$toolhead_variant" != "usb-c" ]]; then
    printf '%b\n' "${R}Invalid --toolhead value '${toolhead_variant}' (expected 'ribbon' or 'usb-c').${NC}"
    exit 1
fi

# Main Script Logic
if [ -z "$1" ]; then
    run_fixes
    set_current_branch
    update_repo

    while true; do
        print_menu
        printf '%b ' "${G}Enter your choice:${NC}"
        read -r choice
        case $choice in
            1) install_printer_cfg ;;
            2) install_configs ;;
            3) wifi_config ;;
            4) update_mcu_rpi_fw ;;
            5) install_screen_service ;;
            6) usb_auto_mount ;;
            7) advanced_more ;;
            q|Q) clear; printf '%b\n' "${G}Goodbye...${NC}"; sleep 2; exit 0 ;;
            *) printf '%b\n' "${R}Invalid choice. Please try again.${NC}" ;;
        esac
    done
else
    run_fixes
    set_current_branch
    COMMAND="$1"
    case "$COMMAND" in
        install_printer_cfg) install_printer_cfg ;;
        install_configs) install_configs ;;
        wifi_config) wifi_config ;;
        update_mcu_rpi_fw) update_mcu_rpi_fw ;;
        install_screen_service) install_screen_service ;;
        usb_auto_mount) usb_auto_mount ;;
        update_repo) update_repo ;;
        android_rules) android_rules ;;
        webcam_setup) webcam_setup ;;
        base_image_config) base_image_config ;;
        armbian_resize) armbian_resize ;;
        *) printf '%b\n' "${R}Invalid command. Please try again.${NC}" ;;
    esac
fi
