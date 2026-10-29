# shellcheck shell=bash
# Menus, help text and the small feature wrappers they call.
# Sourced by OpenNept4une.sh; defines functions only.

advanced_more() {
    while true; do
        clear_screen
        printf '%b\n' "${C}${OPENNEPT4UNE_ART}${NC}"
        printf '%s\n' "=========================================================="
        printf '%b\n' "              OpenNept4une - ${M}Advanced Options${NC} "
        printf '%s\n' "=========================================================="
        printf '\n1) Install Android ADB rules (if using klipperscreen app)\n\n'
        printf '2) Webcam Auto-Config (mjpg-streamer)\n\n'
        printf '3) Resize Active Armbian Partition - for eMMC > 8GB.\n\n'
        printf '4) Update OpenNept4une Repository\n\n'
        printf '%b\n' "${R}-----------------------Risky Options----------------------"
        printf '\n5) Flash/Update Display Firmware (Alpha)\n\n'
        printf '6) Switch Git repo between main/dev\n\n'
        printf '7) Base ZNP-K1 Compiled Image Config (NOT for OpenNept4une)\n\n'
        printf '8) Change Machine Model / Board Version / Motor Current\n\n'
        printf '9) Update SSH server keys\n\n'
        printf '%b\n' "----------------------------------------------------------${NC}"
        printf '10) Create Github Issue Zip\n\n'
        printf '\n%b\n' "(${Y} B ${NC}) Back to Main Menu"
        printf '%s\n' "=========================================================="
        printf '%b' "${G}Enter your choice:${NC} "
        read -r choice

        case $choice in
            1) android_rules;;
            2) webcam_setup;;
            3) armbian_resize;;
            4) update_repo;;
            5) display_firmware;;
            6) toggle_branch;;
            7) base_image_config;;
            8) "${HOME}/OpenNept4une/img-config/set-printer-model.sh"; exit 0;;
            9) update_ssh_keys;;
            10) "${HOME}/OpenNept4une/img-config/github-issue-debug.sh"; exit 0;;
            b|B) return;;  # Return to the main menu
            *) printf '%b\n' "${R}Invalid choice, please try again.${NC}";;
        esac

        read -r -p "$(printf '%b' "${G}Press enter to continue...${NC}")"
    done
}

android_rules() {
    install_feature "Android ADB Rules" "$ANDROID_RULE_INSTALLER" "Do you want to install the android ADB rules? (may fix klipperscreen issues)"
}

webcam_setup() {
    install_feature "Webcam Setup" "$WEBCAM_SETUP_INSTALLER" "Do you want to configure mjpg-streamer?"
}

base_image_config() {
    install_feature "Base Armbian Image Config" "$BASE_IMAGE_INSTALLER" "Do you want to configure a base/fresh armbian image that you compiled?"
}

update_ssh_keys() {
    install_feature "SSH Key Update" "$SSH_KEY_INSTALLER" "Do you want to update the SSH server keys?"
}

armbian_resize() {
    local resize_commands="sudo systemctl enable armbian-resize-filesystem && sudo reboot"
    install_feature "Armbian Resize" "$resize_commands" "Reboot then resize Armbian filesystem?"
}

wifi_config() {
    sudo nmtui
}

usb_auto_mount() {
    install_feature "USB Auto Mount" "$USB_STORAGE_AUTOMOUNT" "Do you want to auto mount USB drives?"
}

update_mcu_rpi_fw() {
    install_feature "MCU Updater" "$MCU_RPI_INSTALLER" "Do you want to update the MCUs?"
}

reboot_system() {
    sync
    clear_screen
    printf '%b\n' "${C}${OPENNEPT4UNE_ART}${NC}"
    printf '\n'
    local REBOOT_CHOICE=""
    if [ "$auto_yes" != "true" ]; then
        printf '%s\n\n' "${Y}The system needs to be rebooted to continue. Reboot now? (y/n).${NC}"
        read -r -p "$(printf '%b' "${M}Enter your choice (highly advised)${NC}: ")" REBOOT_CHOICE
    else
        REBOOT_CHOICE="y"
    fi

    if [[ "$REBOOT_CHOICE" =~ ^[Yy]$ ]]; then
        printf '\n%s\n' "${G}System will reboot now.${NC}"
        sleep 1
        sudo reboot
    else
        printf '%s\n' "${Y}Reboot canceled.${NC}"
        sleep 1
    fi
}

print_help() {
    cat << EOF
Usage: $0 [OPTIONS] COMMAND
OpenNept4une configuration script.

Options:
  -y, --yes                  Automatically confirm all prompts (non-interactive mode).
  --printer_model=MODEL      Specify the printer model (e.g., n4, n4pro, n4plus / n4max).
  --motor_current=VALUE      Specify the stepper motor current (e.g., 0.8, 1.2).
  --toolhead=TYPE            Specify the printhead variant: ribbon (default) or usb-c.
  -h, --help                 Display this help message and exit.

Commands:
  install_printer_cfg        Install or update the OpenNept4une Printer.cfg and other configurations.
  install_configs            Install or update KAMP/Moonraker/fluiddGUI confs, etc.
  wifi_config                Launch NMTUI for WiFi configuration.
  update_mcu_rpi_fw          Update MCU & Virtual MCU RPi firmware.
  install_screen_service     Install or update the Touch-Screen Display Service (BETA).
  usb_auto_mount             Enable USB storage auto-mount feature.
  update_repo                Update the OpenNept4une repository to the latest version.
  android_rules              Install Android ADB rules (for klipperscreen).
  webcam_setup               Install webcam FPS fix.
  base_image_config          Apply base configuration for a freshly compiled Armbian image.
  armbian_resize             Resize the active Armbian partition (for eMMC > 8GB).

EOF
}

print_menu() {
    clear_screen
    printf '%b\n' "${C}${OPENNEPT4UNE_ART}${NC}"
    printf '%s%s%s\n' "    Branch:" "$current_branch" " | Model:$MODEL_FROM_FLAG | Kernel:$KERNEL_FROM_FLAG"
    printf '%s\n' "=========================================================="
    printf '%b\n' "                OpenNept4une - ${M}Main Menu${NC}       "
    printf '%s\n' "=========================================================="
    printf '\n1) Install/Update OpenNept4une printer.cfg\n\n'
    printf '2) Install/Update KAMP/Moonraker/fluiddGUI confs\n\n'
    printf '3) Configure WiFi\n\n'
    printf '4) Update MCU & Virtual MCU Firmware\n\n'
    printf '5) Install/Update Touch-Screen Service (BETA)\n\n'
    printf '6) Enable USB Storage AutoMount\n\n'
    printf '%b\n' "7) ${M}* Advanced Options Menu *${NC}"
    printf '\n%b\n' "(${R} Q ${NC}) Quit"
    printf '%s\n' "=========================================================="
    printf '%s\n' "Select an option by entering (1-7 / q):"
}
