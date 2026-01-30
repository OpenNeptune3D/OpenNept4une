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

clear_screen() {
    # Clear the screen and move the cursor to the top left
    clear
    tput cup 0 0
}

run_fixes() {
    # Get current user dynamically instead of hardcoding 'mks'
    CURRENT_USER="${USER:-$(whoami)}"
    
    # Add current user to 'gpio' and 'spiusers' groups for GPIO and SPI access
    if ! sudo usermod -aG gpio,spiusers "$CURRENT_USER" &>/dev/null; then
        printf '%s\n' "${R}Failed to add user '$CURRENT_USER' to groups 'gpio' and 'spiusers'${NC}"
    fi

    # Ensure NetworkManager override for Wi-Fi power-save exists
    NM_CONF_DIR="/etc/NetworkManager/conf.d"
    NM_PS_FILE="${NM_CONF_DIR}/zz-20-override-wifi-powersave-disable.conf"
    if [ ! -f "$NM_PS_FILE" ]; then
        if ! sudo mkdir -p "$NM_CONF_DIR"; then
            printf '%s\n' "${R}Failed to create $NM_CONF_DIR${NC}"
        elif ! sudo tee "$NM_PS_FILE" >/dev/null <<'EOF'
[connection]
wifi.powersave = 2
EOF
        then
            printf '%s\n' "${R}Failed to create $NM_PS_FILE${NC}"
        else
            sudo systemctl restart NetworkManager >/dev/null 2>&1
        fi
    fi

    # Remove obsolete GPIO script if it exists
    if [ -f "/usr/local/bin/set_gpio.sh" ]; then
        if ! sudo rm -f "/usr/local/bin/set_gpio.sh"; then
            printf '%s\n' "${R}Failed to remove /usr/local/bin/set_gpio.sh${NC}"
        fi
    fi

    # Ensure the flag file exists to mark completion of fixes
    if ! sudo touch "$FLAG_FILE"; then
        printf '%s\n' "${R}Failed to ensure flag file exists at $FLAG_FILE${NC}"
    fi

    # Append system information to the flag file if not already present
    SYSTEM_INFO=$(uname -a)
    if ! sudo grep -qF "$SYSTEM_INFO" "$FLAG_FILE" 2>/dev/null; then
        if ! echo "$SYSTEM_INFO" | sudo tee -a "$FLAG_FILE" >/dev/null; then
            printf '%s\n' "${R}Failed to append system info to $FLAG_FILE${NC}"
        fi
    fi

    # Create a symbolic link for OpenNept4une Logo in fluidd
    ln -sf "${HOME}/OpenNept4une/pictures/logo_opennept4une.svg" "${HOME}/fluidd/logo_opennept4une.svg" > /dev/null 2>&1

    # Create a symbolic link to the main script if it doesn't exist
    SYMLINK_PATH="/usr/local/bin/opennept4une"
    if [ ! -L "$SYMLINK_PATH" ]; then
        if ! sudo ln -sf "$SCRIPT" "$SYMLINK_PATH"; then
            printf '%s\n' "${R}Failed to create symlink at $SYMLINK_PATH${NC}"
        fi
    fi

    # Add /bin/sync to crontab if not present
    if ! (crontab -l 2>/dev/null | grep -q "/bin/sync"); then
        (crontab -l 2>/dev/null | grep -v '/bin/sync'; echo "*/10 * * * * /bin/sync") | crontab -
    fi

    # Create a power_monitor.service if not present
    if [ ! -f "/etc/systemd/system/power_monitor.service" ]; then
        sudo tee "/etc/systemd/system/power_monitor.service" > /dev/null <<EOF
[Unit]
Description=Power Cut Monitor and Safe Shutdown

[Service]
Type=simple
ExecStart=/home/mks/OpenNept4une/img-config/power_monitor.sh
User=root
Restart=no

[Install]
WantedBy=multi-user.target
EOF
        sudo systemctl daemon-reload > /dev/null 2>&1
        sudo systemctl enable power_monitor.service > /dev/null 2>&1
        sudo systemctl start power_monitor.service > /dev/null 2>&1
    fi

    # Make systemd-logind ignore power key / long press (silent, idempotent)
    LOGIND_CONF="/etc/systemd/logind.conf"
    if [ -f "$LOGIND_CONF" ]; then
        if ! sudo grep -q '^HandlePowerKey=ignore$' "$LOGIND_CONF" || \
           ! sudo grep -q '^HandlePowerKeyLongPress=ignore$' "$LOGIND_CONF"; then
            sudo cp "$LOGIND_CONF" "${LOGIND_CONF}.bak" 2>/dev/null || true
            sudo sed -i 's/^[#]*HandlePowerKey=.*/HandlePowerKey=ignore/' "$LOGIND_CONF" 2>/dev/null || true
            sudo sed -i 's/^[#]*HandlePowerKeyLongPress=.*/HandlePowerKeyLongPress=ignore/' "$LOGIND_CONF" 2>/dev/null || true
            sudo systemctl restart systemd-logind >/dev/null 2>&1 || true
        fi
    fi
}

update_repo() {
    clear_screen
    printf '%b\n' "${C}${OPENNEPT4UNE_ART}${NC}"
    printf '\n'
    printf '%s\n' "=========================================================="
    printf '%b\n' "${M}Checking for updates...${NC}"
    printf '%s\n\n' "=========================================================="

    process_repo_update "$OPENNEPT4UNE_DIR" "OpenNept4une"
    moonraker_update_manager "OpenNept4une"

    if [ -d "${HOME}/OpenNept4une/display/venv" ]; then
        printf '%b' "${Y}The Touch-Screen Display Service was moved to a different directory. Do you want to run the automatic migration?${NC} (Y/n): "
        read -r user_input
        if [[ $user_input =~ ^[Yy]$|^$ ]]; then
            if initialize_display_connector && eval "$DISPLAY_SERVICE_INSTALLER"; then
                rm -rf "${HOME}/OpenNept4une/display"
            fi
        else
            printf '%b\n' "${Y}Skipping migration. ${R}The Display Service will not work until the migration is completed.${NC}"
            sleep 2
        fi
    else
        if [ -d "$DISPLAY_CONNECTOR_DIR" ]; then
            process_repo_update "$DISPLAY_CONNECTOR_DIR" "Display Connector"
            moonraker_update_manager "display"
        fi
    fi

    if [ -d "${HOME}/display_firmware/venv" ]; then
        process_repo_update "$DISPLAY_FIRMWARE_DIR" "Display Firmware"
        moonraker_update_manager "display_firmware"
    else
        printf '%b\n' "${Y}Skipping Display Firmware update: $DISPLAY_FIRMWARE_DIR does not exist.${NC}"
    fi

    printf '%s\n' "=========================================================="
}

process_repo_update() {
    local repo_dir="$1"
    local name="$2"
    local update_branch
    local REPLY=""
    
    update_branch=$(git -C "$repo_dir" branch --show-current 2>/dev/null)

    if [ ! -d "$repo_dir" ]; then
        printf '%b\n' "${R}Repository directory not found at $repo_dir!${NC}"
        sleep 5
        return 1
    fi

    if [ -z "$update_branch" ]; then
        printf '%b\n' "${R}Could not determine the current branch for $repo_dir!${NC}"
        sleep 5
        return 1
    fi

    # Fetch updates
    if ! git -C "$repo_dir" fetch origin "$update_branch" --quiet; then
        printf '%b\n' "${R}Failed to fetch updates for ${name}.${NC}"
        sleep 5
        return 1
    fi

    LOCAL=$(git -C "$repo_dir" rev-parse '@')
    REMOTE=$(git -C "$repo_dir" rev-parse '@{u}')

    if [ "$LOCAL" != "$REMOTE" ]; then
        printf '%b\n' "${Y}Updates are available for ${name}.${NC}"
        if [ "$auto_yes" != "true" ]; then
            printf '%s' "Would you like to update ${G}● ${name}?${NC} (y/n): "
            read -r REPLY
        else
            REPLY="y"
        fi

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            printf '%s\n' "Updating..."
            # Attempt to pull and capture any errors
            if ! UPDATE_OUTPUT=$(git -C "$repo_dir" pull origin "$update_branch" 2>&1); then
                # Check for the specific divergent branches error message
                if echo "$UPDATE_OUTPUT" | grep -q "divergent branches"; then
                    printf '%b\n' "${R}Divergent branches detected, performing a hard reset to origin/${update_branch}...${NC}"
                    sleep 1
                    if ! git -C "$repo_dir" reset --hard "origin/${update_branch}"; then
                        printf '%b\n' "${R}Failed to hard reset ${name}.${NC}"
                        sleep 1
                        return 1
                    fi
                    if ! git -C "$repo_dir" clean -fd; then
                        printf '%b\n' "${R}Failed to clean ${name}.${NC}"
                        sleep 1
                        return 1
                    fi
                else
                    printf '%b\n' "${R}Failed to update ${name}: $UPDATE_OUTPUT${NC}"
                    sleep 1
                    return 1
                fi
            fi

            printf '%b\n' "${name} ${G}Updated successfully.${NC}"
            sleep 1
        else
            printf '%b\n' "${Y}Update skipped.${NC}"
            sleep 1
        fi
    else
        printf '%b\n\n' "${G}●${NC} ${name} ${G}is already up-to-date.${NC}"
        sleep 1
    fi

    printf '%s\n\n' "=========================================================="
}

moonraker_update_manager() {
    local update_selection="$1"
    local config_file="$HOME/printer_data/config/moonraker.conf"
    local new_lines=""

    if [ "$update_selection" = "OpenNept4une" ]; then
        local current_ON_branch
        current_ON_branch=$(git -C "$OPENNEPT4UNE_DIR" symbolic-ref --short HEAD 2>/dev/null)
        new_lines=$(cat <<EOF
[update_manager $update_selection]
type: git_repo
primary_branch: $current_ON_branch
path: $OPENNEPT4UNE_DIR
is_system_service: False
origin: $OPENNEPT4UNE_REPO
EOF
)

    elif [ "$update_selection" = "display" ]; then
        local current_display_branch
        current_display_branch=$(git -C "$DISPLAY_CONNECTOR_DIR" symbolic-ref --short HEAD 2>/dev/null)
        new_lines=$(cat <<EOF
[update_manager $update_selection]
type: git_repo
primary_branch: $current_display_branch
path: $DISPLAY_CONNECTOR_DIR
virtualenv: $DISPLAY_CONNECTOR_DIR/venv
requirements: requirements.txt
origin: $DISPLAY_CONNECTOR_REPO
EOF
)

    elif [ "$update_selection" = "display_firmware" ]; then
        local current_firmware_branch
        current_firmware_branch=$(git -C "$DISPLAY_FIRMWARE_DIR" symbolic-ref --short HEAD 2>/dev/null)
        new_lines=$(cat <<EOF
[update_manager $update_selection]
type: git_repo
primary_branch: $current_firmware_branch
path: $DISPLAY_FIRMWARE_DIR
is_system_service: False
virtualenv: $DISPLAY_FIRMWARE_DIR/venv
requirements: requirements.txt
origin: $DISPLAY_FIRMWARE_REPO
EOF
)

    else
        printf '%b\n' "${R}Invalid argument. Please specify either 'OpenNept4une', 'display', or 'display_firmware'.${NC}"
        return 1
    fi
    
    # Update or append block
    if grep -qF "[update_manager $update_selection]" "$config_file" 2>/dev/null; then
        # Use awk for safer in-place editing
        local temp_file
        temp_file=$(mktemp)
        awk -v section="[update_manager $update_selection]" -v new_content="$new_lines" '
        BEGIN { in_section=0; printed=0 }
        $0 == section { in_section=1; print new_content; printed=1; next }
        in_section && /^\[/ { in_section=0 }
        !in_section { print }
        ' "$config_file" > "$temp_file"
        
        if [ -s "$temp_file" ]; then
            mv "$temp_file" "$config_file"
            sync
        else
            rm -f "$temp_file"
        fi
    else
        if [ -s "$config_file" ] && [ "$(tail -c1 "$config_file" 2>/dev/null)" != $'\n' ]; then
            echo >> "$config_file"
        fi
        printf "\n%s\n" "$new_lines" >> "$config_file"
    fi
}

set_current_branch() {
    current_branch=$(git -C "$OPENNEPT4UNE_DIR" symbolic-ref --short HEAD 2>/dev/null)
}

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

install_feature() {
    local feature_name="$1"
    local action="$2"  # This can be a script path or direct commands
    local prompt_message="$3"

    clear_screen
    printf '%b\n' "${C}${OPENNEPT4UNE_ART}${NC}"
    printf '%s\n' "=========================================================="
    printf '%s\n' "$feature_name ${M}Installation${NC}"
    printf '%s\n' "=========================================================="

    local user_input=""
    if [ "$auto_yes" != "true" ]; then
        printf '%b ' "${M}$prompt_message (Y/n)${NC}: "
        read -r user_input
        printf '\n'
    fi

    if [[ $user_input =~ ^[Yy]$|^$ ]] || [ "$auto_yes" = "true" ]; then
        printf '%s\n\n' "Running $feature_name Installer..."
        
        # Check if action is a file (script) or a command
        if [[ -f "$action" ]]; then
            if bash "$action"; then
                printf '%b\n' "${G}$feature_name Installer ran successfully.${NC}"
                sleep 2
            else
                printf '%b\n' "${R}$feature_name Installer encountered an error.${NC}"
                sleep 1
            fi
        elif [[ -n "$action" ]]; then
            if eval "$action"; then
                printf '%b\n' "${G}$feature_name Installer ran successfully.${NC}"
                sleep 2
            else
                printf '%b\n' "${R}$feature_name Installer encountered an error.${NC}"
                sleep 1
            fi
        else
            printf '%b\n' "${R}Error: Action for $feature_name not found or not specified.${NC}"
            sleep 1
        fi
    else
        printf '%b\n' "${Y}Installation skipped.${NC}"
        sleep 1
    fi

    printf '%s\n' "=========================================================="
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

toggle_branch() {
    clear_screen
    printf '%b\n' "${C}${OPENNEPT4UNE_ART}${NC}"
    printf '\n'

    switch_branch() {
        local branch_name="$1"
        local repo_dir="$2"
        if [ -d "$repo_dir" ]; then
            git -C "$repo_dir" reset --hard >/dev/null 2>&1
            git -C "$repo_dir" clean -fd >/dev/null 2>&1
            if git -C "$repo_dir" checkout "$branch_name" >/dev/null 2>&1; then
                printf '%b\n' "${G}Switched $repo_dir to $branch_name.${NC}"
                return 0
            fi
        fi
        return 1
    }

    if [ -d "$OPENNEPT4UNE_DIR" ]; then
        if [ -n "$current_branch" ]; then
            printf '%s' "You are currently on the ${G}'$current_branch'${NC} branch. "
            local target_branch
            if [ "$current_branch" = "main" ]; then
                target_branch="dev"
            else
                target_branch="main"
            fi
            printf '%b ' "${M}Would you like to switch to the '$target_branch' branch?${NC} (y/n): "
            read -r user_response
            if [[ $user_response =~ ^[Yy]$ ]]; then
                # Switch OpenNept4une repo (always present)
                if switch_branch "$target_branch" "$OPENNEPT4UNE_DIR"; then
                    moonraker_update_manager "OpenNept4une"
                fi
                
                # Switch display_connector repo only if it exists
                if switch_branch "$target_branch" "$DISPLAY_CONNECTOR_DIR"; then
                    moonraker_update_manager "display"
                fi
                
                # Switch display_firmware repo only if it exists and has venv (indicating it's installed)
                if [ -d "${DISPLAY_FIRMWARE_DIR}/venv" ] && switch_branch "$target_branch" "$DISPLAY_FIRMWARE_DIR"; then
                    moonraker_update_manager "display_firmware"
                fi
                
                printf '%b\n' "${G}Branch switch operation completed.${NC}"
                sync
                sudo service moonraker restart
                exec "$SCRIPT"
                exit 0
            else
                printf '%b\n' "${Y}Branch switch operation aborted.${NC}"
            fi
        else
            printf '%b\n' "${R}Could not determine the current branch for $OPENNEPT4UNE_DIR.${NC}"
        fi
    else
        printf '%b\n' "${R}$OPENNEPT4UNE_DIR does not exist or is not accessible.${NC}"
    fi
}

display_firmware() {
    clear_screen
    printf '%b\n' "${C}${OPENNEPT4UNE_ART}${NC}"
    printf '\n'

    if [ -z "$current_branch" ]; then
        printf '%s\n' "Error: current_branch is not set. Exiting."
        exit 1
    fi

    if [ ! -d "$DISPLAY_FIRMWARE_DIR" ]; then
        if git clone -b "$current_branch" "${DISPLAY_FIRMWARE_REPO}" "${DISPLAY_FIRMWARE_DIR}"; then
            printf '%b\n' "${G}Initialized repository for Display Firmware Scripts.${NC}"
        else
            printf '%b\n' "${R}Failed to clone Display Firmware repository.${NC}"
            return 1
        fi
    fi

    install_feature "Flash/Update Display Firmware (Alpha)" "$UPDATED_DISPLAY_FIRMWARE_INSTALLER" "Do you want to run Flash/Update Display Firmware (Alpha)?"
}

check_and_set_printer_model() {
    if [ -z "$MODEL_FROM_FLAG" ]; then
        printf '%s\n' "Model Flag is empty. Running Set Model script..."
        if [ -f "${HOME}/OpenNept4une/img-config/set-printer-model.sh" ]; then
            "${HOME}/OpenNept4une/img-config/set-printer-model.sh"
        else
            printf '%b\n' "${R}Error: set-printer-model.sh not found.${NC}"
            return 1
        fi
        MODEL_FROM_FLAG=$(grep -E '^N4|^n4' "$FLAG_FILE" 2>/dev/null)
        if [ -z "$MODEL_FROM_FLAG" ]; then
            printf '%s\n' "Failed to set Model Flag. Exiting."
            return 1
        else
            printf '%s\n' "Model Flag set successfully."
        fi
        return 0
    else
        printf '%s\n' "Model Detected: $MODEL_FROM_FLAG"
        return 0
    fi
}

extract_model_and_motor() {
    model_key=$(echo "$MODEL_FROM_FLAG" | cut -d'-' -f1 | tr '[:upper:]' '[:lower:]')
    motor_current=$(echo "$MODEL_FROM_FLAG" | sed -E 's/^[^-]*-([0-9.]+)A.*/\1/')
    pcb_version=$(echo "$MODEL_FROM_FLAG" | sed -E 's/.*-v([0-9.]+).*/\1/')
}

install_printer_cfg() {
    clear_screen
    printf '%b\n' "${C}${OPENNEPT4UNE_ART}${NC}"
    printf '\n'

    if ! check_and_set_printer_model; then
        return 1
    fi
    sleep 1

    extract_model_and_motor

    PRINTER_CFG_DEST="${HOME}/printer_data/config"
    DATABASE_DEST="${HOME}/printer_data/database"
    PRINTER_CFG_FILE="$PRINTER_CFG_DEST/printer.cfg"
    PRINTER_CFG_SOURCE="${HOME}/OpenNept4une/printer-confs/output.cfg"

    # Build config based on user selection
    if [[ $model_key == "n4" || $model_key == "n4pro" ]]; then
        if ! python3 "${HOME}/OpenNept4une/printer-confs/generate_conf.py" "${model_key}" "${motor_current}" >/dev/null 2>&1; then
            printf '%b\n' "${R}Failed to generate printer configuration.${NC}"
            return 1
        fi
        sync
    else
        if ! python3 "${HOME}/OpenNept4une/printer-confs/generate_conf.py" "${model_key}" >/dev/null 2>&1; then
            printf '%b\n' "${R}Failed to generate printer configuration.${NC}"
            return 1
        fi
        sync
    fi
    sleep 1

    mkdir -p "$PRINTER_CFG_DEST" "$DATABASE_DEST"
    touch "${HOME}/printer_data/config/user_settings.cfg"

    printf '%s\n\n' "${G}Would you like to compare/diff your current printer.cfg with the latest? (y/n).${NC}"
    read -r -p "$(printf '%b' "${M}Enter your choice ${NC}: ")" DIFF_CHOICE

    if [[ "$DIFF_CHOICE" =~ ^[Yy]$ ]]; then
        clear_screen
        printf '\n'
        SPACES=$(printf '%*s' 32 '')
        printf '%b%s%b%s\n' "${C}" "Updated File:" "${NC}" "${SPACES}Current File:"
        printf '%b\n' "${C}==========================================================${NC}"

        DIFF_OUTPUT=$(diff -y --suppress-common-lines --width=58 \
            "${HOME}/OpenNept4une/printer-confs/output.cfg" \
            "${HOME}/printer_data/config/printer.cfg" 2>/dev/null
        )

        if [[ -z "$DIFF_OUTPUT" ]]; then
            printf '\n%s\n' "${G}There are no differences, Already up-to-date! ${NC}"
        else
            printf '%s\n' "$DIFF_OUTPUT"
        fi

        printf '\n%s\n\n' "${Y}Would you like to continue with the update? (y/n).${NC}"
        read -r -p "$(printf '%b' "${M}Enter your choice ${NC}: ")" CONTINUE_CHOICE

        if [[ "$CONTINUE_CHOICE" =~ ^[Yy]$ ]]; then
            printf '\n%s\n' "${G}Continuing with printer.cfg update.${NC}"
            sleep 1
        else
            printf '\n%s\n' "${Y}Exiting the update process.${NC}"
            sleep 1
            return 0
        fi
    else
        printf '\n%s\n' "${G}Continuing with printer.cfg update.${NC}"
        sleep 1
    fi

    apply_configuration
    sync
    printf '\n%s\n' "${Y}Restarting Klipper Service${NC}"
    sleep 2
    sudo service klipper restart
}

apply_configuration() {
    local backup_count=1
    local BACKUP_PRINTER_CFG_FILE="$PRINTER_CFG_DEST/backup-printer.cfg.bak$backup_count"
    
    while [[ -f "$BACKUP_PRINTER_CFG_FILE" ]]; do
        ((backup_count++))
        BACKUP_PRINTER_CFG_FILE="$PRINTER_CFG_DEST/backup-printer.cfg.bak$backup_count"
    done

    if [[ -f "$PRINTER_CFG_FILE" ]]; then
        if cp "$PRINTER_CFG_FILE" "$BACKUP_PRINTER_CFG_FILE"; then
            printf '\n%s\n\n' "${G}BACKUP of 'printer.cfg' created as '${BACKUP_PRINTER_CFG_FILE}'.${NC}"
            sleep 2
        else
            printf '%s\n' "${R}Error: Failed to create backup of 'printer.cfg'.${NC}"
        fi
        sleep 1
    fi

    if [[ -n "$PRINTER_CFG_SOURCE" && -f "$PRINTER_CFG_SOURCE" ]]; then
        if cp "$PRINTER_CFG_SOURCE" "$PRINTER_CFG_FILE"; then
            printf '%s\n\n' "${G}Printer configuration updated from '${PRINTER_CFG_SOURCE}'.${NC}"
            sleep 2
        else
            printf '%s\n' "${R}Error: Failed to update printer configuration from '${PRINTER_CFG_SOURCE}'.${NC}"
            sleep 1
        fi
    else
        printf '%s\n' "${R}Error: Invalid printer configuration file '${PRINTER_CFG_SOURCE}'.${NC}"
        return 1
    fi
}

install_configs() {
    clear_screen
    printf '%b\n' "${C}${OPENNEPT4UNE_ART}${NC}"
    printf '\n'

    # Menu label -> space-separated file list
    declare -A config_files=(
        ["All"]=""
        ["Fluidd web interface Conf"]="data.mdb"
        ["Moonraker Conf"]="moonraker.conf moonraker.asvc"
        ["KAMP Conf"]="KAMP_Settings.cfg"
        ["Mainsail web interface Conf"]="mainsail.cfg"
        ["Pico USB-C ADXL Conf"]="adxl.cfg"
        ["Klipper DEBUG Addon"]="klipper_debug.cfg"
    )

    # ----------------- Helpers -----------------

    dest_path_for() {
        local f="$1"
        case "$f" in
            data.mdb)          printf '%s\n' "${HOME}/printer_data/database/data.mdb" ;;
            moonraker.asvc)    printf '%s\n' "${HOME}/printer_data/moonraker.asvc" ;;
            *)                 printf '%s\n' "${HOME}/printer_data/config/${f}" ;;
        esac
    }

    install_one() {
        local f="$1"
        local src="${HOME}/OpenNept4une/img-config/printer-data/${f}"
        local dst; dst="$(dest_path_for "$f")"

        if [[ ! -f "$src" ]]; then
            printf '%b\n' "${R}Source missing: ${src}${NC}"
            return 1
        fi

        local dstdir; dstdir="$(dirname "$dst")"
        mkdir -p "$dstdir"

        if [[ "$f" == "data.mdb" ]]; then
            mkdir -p "${HOME}/printer_data/config" "${HOME}/printer_data/database"
            local tmp="${HOME}/printer_data/config/data.mdb"
            cp -f "$src" "$tmp"
            mv -f "$tmp" "$dst"
        else
            cp -f "$src" "$dst"
        fi

        printf '%s\n' "${G}${f} installed to ${dst}.${NC}"
    }

    maybe_diff() {
        local f="$1"
        if [[ "$f" == "data.mdb" ]]; then
            printf '%s\n' "${Y}Skipping diff for binary file: ${f}.${NC}"
            return 2
        fi

        local src="${HOME}/OpenNept4une/img-config/printer-data/${f}"
        local cur; cur="$(dest_path_for "$f")"

        if [[ ! -f "$src" ]]; then
            printf '%b\n' "${R}Source missing for diff: ${src}${NC}"
            return 1
        fi
        if [[ ! -f "$cur" ]]; then
            printf '%s\n' "${Y}No current file found for ${f}; nothing to diff.${NC}"
            return 3
        fi

        local out
        out="$(diff -y --suppress-common-lines --width=90 "$src" "$cur" 2>/dev/null || true)"
        if [[ -z "$out" ]]; then
            printf '%s\n' "${G}No differences for ${f}; up-to-date.${NC}"
            return 4
        fi

        printf '%b\n' "${C}Differences for ${f}:${NC}"
        printf '%s\n' "$out"
        return 0
    }

    # ----------------- Prompt / flow -----------------

    local install_configs_var="$auto_yes"
    if [[ "$auto_yes" != "true" ]]; then
        printf '%s\n\n' "The latest configurations include updated settings and features for your printer."
        printf '%s\n\n' "${Y}Recommended on fresh installs or when resetting to defaults.${NC}"
        printf '%b' "${M}Select latest configurations to install?${NC} (y/N): "
        local choice; read -r choice
        [[ $choice =~ ^[Yy]$ ]] && install_configs_var="true"
    fi

    if [[ "$install_configs_var" != "true" ]]; then
        printf '%b\n' "${Y}Installation of latest configurations skipped.${NC}"
        sleep 1
        return 0
    fi

    PS3="Enter the number of the configuration to install (or 'Exit' to finish): "
    local options=("All" "Fluidd web interface Conf" "Moonraker Conf" "KAMP Conf" "Mainsail web interface Conf" "Pico USB-C ADXL Conf" "Klipper DEBUG Addon" "Exit")

    while true; do
        clear_screen
        printf '%b\n' "${C}${OPENNEPT4UNE_ART}${NC}"
        printf '\n%s\n' "Select configurations to install:"
        for i in "${!options[@]}"; do
            printf '%2d) %s\n' $((i+1)) "${options[$i]}"
        done

        local opt
        read -rp "$PS3" opt
        case "$opt" in
            1)
                printf '%s\n' "Installing all configurations..."
                for key in "${!config_files[@]}"; do
                    [[ "$key" == "All" ]] && continue
                    local files="${config_files[$key]}"
                    [[ -z "$files" ]] && continue
                    for file in $files; do
                        install_one "$file" || printf '%b\n' "${R}Failed: ${file}${NC}"
                    done
                done
                printf '\n%s\n' "${G}All configurations installed.${NC}"
                sleep 2
                return 0
                ;;
            2|3|4|5|6|7)
                local opt_name="${options[$((opt-1))]}"
                printf '%s\n' "Installing ${opt_name}..."
                local files="${config_files[$opt_name]}"

                printf '\n%s\n' "${G}Compare/diff current ${opt_name} with latest? (y/n)${NC}"
                local DIFF_CHOICE
                read -r -p "$(printf '%b' "${M}Enter your choice ${NC}: ")" DIFF_CHOICE

                if [[ "$DIFF_CHOICE" =~ ^[Yy]$ ]]; then
                    clear_screen
                    printf '\n'
                    for file in $files; do
                        printf '%b\n' "${C}==========================================================${NC}"
                        local diff_rc=0
                        maybe_diff "$file" || diff_rc=$?
                        if [[ $diff_rc -eq 0 || $diff_rc -eq 2 || $diff_rc -eq 3 ]]; then
                            printf '\n%s\n' "${Y}Continue with update for ${file}? (y/n)${NC}"
                            local CONTINUE_CHOICE
                            read -r -p "$(printf '%b' "${M}Enter your choice ${NC}: ")" CONTINUE_CHOICE
                            if [[ ! "$CONTINUE_CHOICE" =~ ^[Yy]$ ]]; then
                                printf '%s\n' "${Y}Skipping ${file}.${NC}"
                                continue
                            fi
                        else
                            # up-to-date; skip install
                            continue
                        fi
                        install_one "$file" || printf '%b\n' "${R}Failed: ${file}${NC}"
                    done

                    printf '\n%s\n' "${Y}Install another configuration? (y/n)${NC}"
                    local CONTINUE_CHOICE
                    read -r -p "$(printf '%b' "${M}Enter your choice ${NC}: ")" CONTINUE_CHOICE
                    if [[ "$CONTINUE_CHOICE" =~ ^[Nn]$ ]]; then
                        printf '\n%s\n' "${Y}Exiting the update process.${NC}"
                        sleep 1
                        break
                    fi
                    printf '\n%s\n' "${G}Returning to configuration selection.${NC}"
                    sleep 1
                else
                    printf '\n%s\n' "${G}Continuing with ${opt_name} update.${NC}"
                    sleep 1
                    for file in $files; do
                        install_one "$file" || printf '%b\n' "${R}Failed: ${file}${NC}"
                    done
                fi

                printf '%s\n' "${G}${opt_name} installed successfully.${NC}"
                ;;
            8)
                printf '%s\n' "${Y}Exiting the update process.${NC}"
                break
                ;;
            *)
                printf '%b\n' "${R}Invalid selection. Please try again.${NC}"
                ;;
        esac
    done

    printf '%s\n\n' "${G}Selected configurations installed successfully.${NC}"
    sleep 1
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

install_screen_service() {
    install_feature "Touch-Screen Display Service" run_install_screen_service_with_setup "Do you want to install the Touch-Screen Display Service?"
}

run_install_screen_service_with_setup() {
    rm -rf "${HOME}/display_connector"
    if initialize_display_connector && [ -f "$DISPLAY_SERVICE_INSTALLER" ]; then
        bash "$DISPLAY_SERVICE_INSTALLER"
    else
        printf '%b\n' "${R}Failed to initialize display connector or installer not found.${NC}"
        return 1
    fi
}

initialize_display_connector() {
    if [ ! -d "${HOME}/display_connector" ]; then
        if git clone -b "$current_branch" "${DISPLAY_CONNECTOR_REPO}" "${DISPLAY_CONNECTOR_DIR}"; then
            printf '%b\n' "${G}Initialized repository for Touch-Screen Display Service.${NC}"
        else
            printf '%b\n' "${R}Failed to clone Display Connector repository.${NC}"
            return 1
        fi
    fi
    moonraker_update_manager "display"
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

# Parse Command-Line Arguments
if ! TEMP=$(getopt -o yh --long yes,help,printer_model:,motor_current:,pcb_version: -n 'OpenNept4une.sh' -- "$@"); then
    printf '%b\n' "${R}Failed to parse options.${NC}" >&2
    exit 1
fi

eval set -- "$TEMP"

while true; do
    case "$1" in
        --printer_model) model_key="$2"; shift 2 ;;
        --motor_current) motor_current="$2"; shift 2 ;;
        --pcb_version) pcb_version="$2"; shift 2 ;;
        -y|--yes) auto_yes="true"; shift ;;
        -h|--help) print_help; exit 0 ;;
        --) shift; break ;;
        *) printf '%b\n' "${R}Invalid option: $1 ${NC}"; exit 1 ;;
    esac
done

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
