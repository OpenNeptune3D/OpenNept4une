#!/bin/bash

# Path to the script and other resources
SCRIPT="${HOME}/OpenNept4une/OpenNept4une.sh"
DISPLAY_SERVICE_INSTALLER="${HOME}/OpenNept4une/display/display-service-installer.sh"
MCU_RPI_INSTALLER="${HOME}/OpenNept4une/img-config/rpi-mcu-install.sh"
USB_STORAGE_AUTOMOUNT="${HOME}/OpenNept4une/img-config/usb-storage-automount.sh"
ANDROID_RULE_INSTALLER="${HOME}/OpenNept4une/img-config/adb-automount.sh"
CROWSNEST_FIX_INSTALLER="${HOME}/OpenNept4une/img-config/crowsnest-lag-fix.sh"
BASE_IMAGE_INSTALLER="${HOME}/OpenNept4une/img-config/base_image_configuration.sh"
DE_ELEGOO_IMAGE_CLEANSER="${HOME}/OpenNept4une/img-config/de_elegoo_cleanser.sh"
FLAG_FILE="/boot/.OpenNept4une.txt"

# Command line arguments
PRINTER_MODEL=
MOTOR_CURRENT=
PCB_VERSION=
SAY_YES=false

run_fixes() {
    # Image Fixes 
    sudo usermod -aG gpio,spiusers mks &>/dev/null
    sudo rm -f /usr/local/bin/set_gpio.sh

    # Ensure the flag file exists and update its timestamp
    sudo touch "$FLAG_FILE"

    # Get system information
    SYSTEM_INFO=$(uname -a)

    # Check if the system information is already in the flag file and append it if not
    if ! sudo grep -qF "$SYSTEM_INFO" "$FLAG_FILE"; then
        echo "$SYSTEM_INFO" | sudo tee -a "$FLAG_FILE" > /dev/null
    fi

    # Check if symlink for this file exists
    if [ ! -f "/usr/local/bin/opennept4une" ]; then
        sudo ln -s "$SCRIPT" /usr/local/bin/opennept4une
    fi
}

# ASCII art for OpenNept4une 
OPENNEPT4UNE_ART=$(cat <<'EOF'

  ____                _  __         __  ____              
 / __ \___  ___ ___  / |/ /__ ___  / /_/ / /__ _____  ___ 
/ /_/ / _ \/ -_) _ \/    / -_) _ \/ __/_  _/ // / _ \/ -_)
\____/ .__/\__/_//_/_/|_/\__/ .__/\__/ /_/ \_,_/_//_/\__/ 
    /_/                    /_/                            


EOF
)

clear_screen() {
    # Clear the screen and move the cursor to the top left
    clear
    tput cup 0 0
}

# Function to update the repository
update_repo() {
    clear_screen
    echo -e "\033[0;33m$OPENNEPT4UNE_ART\033[0m"
    echo "======================================"
    echo "Checking for updates..."
    echo "======================================"
    repo_dir="$HOME/OpenNept4une"
    if [ -d "$repo_dir" ]; then
        cd "$repo_dir"
    else
        echo "Repository directory not found!"
        return 1
    fi
    
    # Pull the updates
    git fetch origin main --quiet
    LOCAL=$(git rev-parse @)
    REMOTE=$(git rev-parse @{u})

    if [ "$LOCAL" != "$REMOTE" ]; then
        echo "Updates are available for the repository."
        read -p "Would you like to update the repository? (y/n): " -r
        if [[ $REPLY =~ ^[Yy]$ || $SAY_YES = true ]]; then
            echo "Updating repository..."
            git reset --hard
            git clean -fd
            # Pull the updates
            git pull origin main --force
            exec "$SCRIPT"
            exit 0
        else
            echo "Update skipped."
        fi
    else
        echo "Your repository is already up-to-date."
    fi
    echo "======================================"
}

advanced_more() {
clear_screen
    echo -e "\033[0;33m$OPENNEPT4UNE_ART\033[0m"
    echo "======================================"
    echo "Welcome to OpenNept4une"
    echo "======================================"
    echo "1) Install Android ADB rules (klipperscreen)"
    echo ""
    echo "2) Install Crowsnest FPS Fix"
    echo ""
    echo "3) Base ZNP-K1 Compiled Image Config (Dont use on release images)"
    echo ""
    echo "4) Method 2 (No eMMC) - Elegoo Image Cleanser Script - Not Advised"
    echo ""
    echo "5) Resize Active Armbian Partition (for eMMC > 8GB)"
    echo ""
    echo "6) Return Main Menu"
    echo "======================================"

read -p "Enter your choice: " choice
    case $choice in
        1)
            android_rules
            ;;
        2)
            crowsnest_fix
            ;;
        3)
            base_image_config
            ;;
        4)
            de_elegoo_image_cleanser
            ;;
        5)
            armbian_resize
            ;;
        6)
            print_menu
            ;;
    esac
}

android_rules() {
    clear_screen
    echo -e "\033[0;33m$OPENNEPT4UNE_ART\033[0m"
    echo "======================================"
    if [ $SAY_YES = false ]; then
        echo "Do you want to install the android ADB rules? (may fix klipperscreen issues)"
        read -p "Enter 'y' to install, any other key to skip: " install_android_rules
    fi

    if [[ $install_android_rules =~ ^[Yy]$ || $SAY_YES = true ]]; then
        echo "Running ADB Rule Installer..."
        if [ -f "$ANDROID_RULE_INSTALLER" ]; then
            "$ANDROID_RULE_INSTALLER"
        else
            echo "Error: Android rule installer script not found."
        fi
        echo "======================================"
    fi
}

crowsnest_fix() {
    clear_screen
    echo -e "\033[0;33m$OPENNEPT4UNE_ART\033[0m"
    echo "======================================"
    if [ $SAY_YES = false ]; then
        echo "Do you want to install the crowsnest fps fix?"
        read -p "Enter 'y' to install, any other key to skip: " install_crowsnest_fix
    fi

    if [[ $install_crowsnest_fix =~ ^[Yy]$ || $SAY_YES = true ]]; then
        echo "Running crowsnest Fix Installer..."
        if [ -f "$CROWSNEST_FIX_INSTALLER" ]; then
            "$CROWSNEST_FIX_INSTALLER"
        else
            echo "Error: crowsnest fix installer script not found."
        fi
        echo "======================================"
    fi
}

base_image_config() {
    clear_screen
    echo -e "\033[0;33m$OPENNEPT4UNE_ART\033[0m"
    echo "======================================"
    if [ $SAY_YES = false ]; then
        echo "Do you want to configure a base/fresh armbian image that you compiled?"
        read -p "Enter 'y' to install, any other key to skip: " install_base_image_config
    fi

    if [[ $install_base_image_config =~ ^[Yy]$ || $SAY_YES = true ]]; then
        echo "Running base/fresh image Installer..."
        if [ -f "$BASE_IMAGE_INSTALLER" ]; then
            "$BASE_IMAGE_INSTALLER"
        else
            echo "Error: Base Image installer script not found."
        fi
        echo "======================================"
    fi
}

de_elegoo_image_cleanser() {
    clear_screen
    echo -e "\033[0;33m$OPENNEPT4UNE_ART\033[0m"
    echo "======================================"
    echo "DO NOT run this on an OpenNept4une GitHub Image, for Elegoo images only!"
    echo "Continue at your own risk! High chance of requiring a eMMC re-flash!"
    if [ $SAY_YES = false ]; then
        read -p "Enter 'y' to install, any other key to skip: " install_de_elegoo_image_cleanser
    fi

    if [[ $install_de_elegoo_image_cleanser =~ ^[Yy]$ || $SAY_YES = true ]]; then
        echo "Running De-Elegoo Script..."
        if [ -f "$DE_ELEGOO_IMAGE_CLEANSER" ]; then
            "$DE_ELEGOO_IMAGE_CLEANSER"
        else
            echo "Error: De-Elegoo script not found."
        fi
        echo "======================================"
    fi
}

armbian_resize() {
    clear_screen
    echo -e "\033[0;33m$OPENNEPT4UNE_ART\033[0m" 
    echo "======================================"
    echo "The system will reboot then resize after running this script"
    echo "allow it some time to complete (15min) before powering off or rebooting again"
    if [ $SAY_YES = false ]; then
        read -p "Enter 'y' to run, any other key to skip: " run_armbian_resize
    fi
    if [[ $run_armbian_resize =~ ^[Yy]$ || $SAY_YES = true ]]; then
        echo "Running Resize Script..."
        if sudo systemctl enable armbian-resize-filesystem; then
            sudo reboot
        else
            echo "Failed to enable resize service. Check for errors."
        fi
        echo "======================================"
    fi
}

# Function to install the Screen Service
install_screen_service() {
    clear_screen
    echo -e "\033[0;33m$OPENNEPT4UNE_ART\033[0m"
    echo "======================================"
    if [ $SAY_YES = false ]; then
        echo "Do you want to install the Touch-Screen Display Service? (BETA)"
        read -p "Enter 'y' to install, any other key to skip: " install_screen
    fi
    if [[ $install_screen =~ ^[Yy]$ || $SAY_YES = true ]]; then
        echo "Installing Touch-Screen Service..."
        if [ -f "$DISPLAY_SERVICE_INSTALLER" ]; then
            sudo rm -rf ~/OpenNept4une/display/venv
            rm -rf ~/OpenNept4une/display/__pycache__
            "$DISPLAY_SERVICE_INSTALLER"
        else
            echo "Error: Display service installer script not found."
        fi
        echo "======================================"
    fi
}

update_mcu_rpi_fw() {
    clear_screen
    echo -e "\033[0;33m$OPENNEPT4UNE_ART\033[0m"
    echo "======================================"
    if [ $SAY_YES = false ]; then
        echo "Do you want to update the MCU or Virtual MCU?"
        read -p "Enter 'y' to install, any other key to skip: " install_mcu_rpi
    fi

    if [[ $install_mcu_rpi =~ ^[Yy]$ || $SAY_YES = true ]]; then
        echo "Running MCU / MCU RPi Installer..."
        if [ -f "$MCU_RPI_INSTALLER" ]; then
            if [[ $SAY_YES = true ]]; then
                "$MCU_RPI_INSTALLER" "Virtual RPi"
            else
                "$MCU_RPI_INSTALLER"
            fi
        else
            echo "Error: Virtual / MCU installer script not found."
        fi
        echo "======================================"
    fi
}

usb_auto_mount() {
    clear_screen
    echo -e "\033[0;33m$OPENNEPT4UNE_ART\033[0m"
    echo "======================================"
    if [ $SAY_YES = false ]; then
        echo "Do you want to auto mount USB drives? (Folder will mount as 'USB' in fluid 'Jobs' Tab)"
        read -p "Enter 'y' to install, any other key to skip: " install_usb_auto_mount
    fi

    if [[ $install_usb_auto_mount =~ ^[Yy]$ || $SAY_YES = true ]]; then
        echo "Running USB Auto Mount Installer..."
        if [ -f "$USB_STORAGE_AUTOMOUNT" ]; then
            "$USB_STORAGE_AUTOMOUNT"
        else
            echo "Error: USB Auto Mount installer script not found."
        fi
        echo "======================================"
    fi
}

# Function to copy files with error handling
copy_file() {
    local src="$1"
    local dest=$2
    local use_sudo=${3:-false}

    if [[ -f "$src" ]]; then
        if [[ "$use_sudo" == true ]]; then
            sudo cp "$src" "$dest" || {
                echo "Error: Failed to copy $src to $dest."
                return 1
            }
        else
            cp "$src" "$dest" || {
                echo "Error: Failed to copy $src to $dest."
                return 1
            }
        fi
        echo "Successfully copied $src to $dest."
    else
        echo "Error: Source file $src not found."
        return 1
    fi
}

# Function to apply configuration
apply_configuration() {
    if [[ -f "$PRINTER_CFG_FILE" ]]; then
        cp "$PRINTER_CFG_FILE" "$BACKUP_PRINTER_CFG_FILE"
        echo -e "\nBackup of 'printer.cfg' created as 'backup-printer.cfg.bak'.\n"
        sleep 5
    fi

    if [[ -n "$PRINTER_CFG_SOURCE" ]]; then
        copy_file "$PRINTER_CFG_SOURCE" "$PRINTER_CFG_DEST/printer.cfg" false
    else
        echo -e "\nError: Invalid printer configuration file.\n"
        return 1
    fi

    if [[ -n "$DTB_SOURCE" ]]; then
        echo -e "\nDo you wish to update the DTB file? First Run on Git Image MUST select Yes, others skip (y/n)\n"
        read -r REPLY
        echo ""

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            if grep -q "mks" /boot/.OpenNept4une.txt; then
                echo -e "\nSkipping\n"
                sleep 5
            else
                copy_file "$DTB_SOURCE" "$DTB_DEST" true
            fi
        else
            echo -e "\nSkipping DTB file update.\n"
        fi
    else
        echo -e "\nError: Invalid DTB file selection.\n"
        return 1
    fi
    
    # User prompt for installing KAMP/moonraker and fluidd GUI configuration
    if [ $SAY_YES = false ]; then
        echo ""
        echo "Do you wish to install the latest KAMP/moonraker/fluiddGUI configurations? (y/n)"
        echo ""
        read -p "If this is a first-time install, it is recommended. If just updating printer.cfg & you have custom KAMP configurations, it is best to skip: " user_choice
        echo ""
    fi
    
    if [[ "$user_choice" =~ ^[Yy]$ || $SAY_YES = true ]]; then
        # Commands to install the latest configurations
        echo "Installing latest configurations..."
        echo ""
        cp -r ~/OpenNept4une/img-config/printer-data/* ~/printer_data/config/
        mv ~/printer_data/config/data.mdb ~/printer_data/database/data.mdb
    else
        echo -e "\nSkipping the installation of latest configurations.\n"
    fi
}
    
install_printer_cfg() {
    clear_screen
    echo -e "\033[0;33m$OPENNEPT4UNE_ART\033[0m"
    if [[ -z "$PRINTER_MODEL" && $SAY_YES = false ]]; then
        echo "Please select your machine type:"
        echo "1) Neptune4"
        echo "2) Neptune4 Pro"
        echo "3) Neptune4 Plus"
        echo "4) Neptune4 Max"
        read -p "Enter your choice (1-4): " MACHINE_TYPE
    else
        case $PRINTER_MODEL in
            "N4"|"Neptune4"|"Neptune4")
                MACHINE_TYPE=1 ;;
            "N4Pro"|"Neptune4Pro"|"Neptune4 Pro")
                MACHINE_TYPE=2 ;;
            "N4Plus"|"Neptune4Plus"|"Neptune4 Plus")
                MACHINE_TYPE=3 ;;
            "N4Max"|"Neptune4Max"|"Neptune4 Max")
                MACHINE_TYPE=4 ;;
            *)
                echo "Invalid machine type. Please try again."
                exit 1;;
        esac
    fi

    PRINTER_CFG_DEST="${HOME}/printer_data/config"
    DTB_DEST="/boot/dtb/rockchip/rk3328-roc-cc.dtb"
    DATABASE_DEST="${HOME}/printer_data/database"
    PRINTER_CFG_FILE="$PRINTER_CFG_DEST/printer.cfg"
    BACKUP_PRINTER_CFG_FILE="$PRINTER_CFG_DEST/backup-printer.cfg.bak"

    mkdir -p "$PRINTER_CFG_DEST" "$DATABASE_DEST"
    
    update_flag_file() {
    local flag_value=$1
    sudo awk -v line="$flag_value" '
    BEGIN { added = 0 }
    /^N4/ { print line; added = 1; next }
    { print }
    END { if (!added) print line }
    ' "$FLAG_FILE" > temp
    sudo cp temp "$FLAG_FILE" && rm temp # Replacing mv with cp and rm
    }

    stepper_motor_current() {
        if [[ -z "$MOTOR_CURRENT" && $SAY_YES = false ]]; then
            read -p "Enter stepper motor current (0.8 or 1.2): " MOTOR_CURRENT
        fi
        if [[ "$MOTOR_CURRENT" != "0.8" && "$MOTOR_CURRENT" != "1.2" ]]; then
            echo "Invalid motor current selection. Please enter 0.8 or 1.2."
            if [[ $SAY_YES = true ]]; then
                exit 1
            fi
            stepper_motor_current
        fi
    }

    pcb_version() {
        if [[ -z "$PCB_VERSION" && $SAY_YES = false ]]; then
            read -p "Enter PCB Version (1.0 or 1.1): " PCB_VERSION
        fi
        if [[ "$PCB_VERSION" != "1.0" && "$PCB_VERSION" != "1.1" ]]; then
            echo "Invalid PCB selection. Please enter 1.0 or 1.1."
            if [[ $SAY_YES = true ]]; then
                exit 1
            fi
            pcb_version
        fi
    }

    case $MACHINE_TYPE in
        1)
            
            clear_screen
            echo -e "\033[0;33m$OPENNEPT4UNE_ART\033[0m"
            echo "Configuring for Neptune4..."
            stepper_motor_current
            pcb_version
            PRINTER_CFG_SOURCE="${HOME}/OpenNept4une/printer-confs/n4/n4-${MOTOR_CURRENT}-printer.cfg"
            DTB_SOURCE="${HOME}/OpenNept4une/dtb/n4-n4pro-v${PCB_VERSION}/rk3328-roc-cc.dtb"
            FLAG_LINE="N4-${MOTOR_CURRENT}A-v${PCB_VERSION}"
            ;;
        2)
            clear_screen
            echo -e "\033[0;33m$OPENNEPT4UNE_ART\033[0m"
            echo "Configuring for Neptune4 Pro..."
            stepper_motor_current
            pcb_version
            PRINTER_CFG_SOURCE="${HOME}/OpenNept4une/printer-confs/n4pro/n4pro-${MOTOR_CURRENT}-printer.cfg"
            DTB_SOURCE="${HOME}/OpenNept4une/dtb/n4-n4pro-v${PCB_VERSION}/rk3328-roc-cc.dtb"
            FLAG_LINE="N4Pro-${MOTOR_CURRENT}A-v${PCB_VERSION}"
            ;;
        3)
            clear_screen
            echo -e "\033[0;33m$OPENNEPT4UNE_ART\033[0m"
            echo "Configuring for Neptune4 Plus..."
            PRINTER_CFG_SOURCE="${HOME}/OpenNept4une/printer-confs/n4plus/n4plus-printer.cfg"
            DTB_SOURCE="${HOME}/OpenNept4une/dtb/n4plus-n4max-v1.1-2.0/rk3328-roc-cc.dtb"
            FLAG_LINE="N4Plus"
            ;;
        4)
            clear_screen
            echo -e "\033[0;33m$OPENNEPT4UNE_ART\033[0m"
            echo "Configuring for Neptune4 Max..."
            PRINTER_CFG_SOURCE="${HOME}/OpenNept4une/configs/neptune4max/printer.cfg"
            DTB_SOURCE="${HOME}/OpenNept4une/dtb/n4plus-n4max-v1.1-2.0/rk3328-roc-cc.dtb"
            FLAG_LINE="N4Max"
            ;;
        *)
            clear_screen
            echo -e "\033[0;33m$OPENNEPT4UNE_ART\033[0m"
            echo "Invalid selection. Please try again."
            return
            ;;
    esac
    
    update_flag_file "$FLAG_LINE"
    apply_configuration
    reboot_system
}

# Function to reboot the system
reboot_system() {
    clear_screen
    echo -e "\033[0;33m$OPENNEPT4UNE_ART\033[0m"
    if [ $SAY_YES = false ]; then
        echo "The system needs to be rebooted to continue. Reboot now? (y/n)"
        read -p "Enter your choice (highly advised): " REBOOT_CHOICE
    fi
    if [[ "$REBOOT_CHOICE" =~ ^[Yy]$ || $SAY_YES = true ]]; then
        echo "System will reboot now."
        sudo reboot
    else
        echo "Reboot canceled."
    fi
}

# Function to configure WiFi
wifi_config() {
sudo nmtui
}

print_help() {
    echo "Usage: $0 [OPTIONS] COMMAND"
    echo "OpenNept4une configuration script."
    echo ""
    echo "  -y, --yes                   Automatic yes to prompts."
    echo "      --printer_model=MODEL   Specify the printer model."
    echo "      --motor_current=VALUE   Specify the stepper motor current."
    echo "      --pcb_version=VALUE     Specify the PCB version."
    echo "  -h, --help                  Display this help and exit."
    echo ""
    echo "Commands:"
    echo "  install_printer_cfg         Install/Update latest OpenNept4une Printer.cfg + other configs"
    echo "  usb_auto_mount              Enable USB Storage AutoMount"
    echo "  update_mcu_rpi_fw           Update MCU & (Virtual) MCU RPi Firmware"
    echo "  install_screen_service      Install/Update Touch-Screen Display Service (BETA)"
    echo "  update_repo                 Update repository"
    echo "  android_rules               Install Android ADB rules (klipperscreen)"
    echo "  crowsnest_fix               Install Crowsnest FPS Fix"
    echo "  base_image_config           Base ZNP-K1 Compiled Image Config (Dont use on release images)"
    echo "  de_elegoo_image_cleanser    Method 2 (No eMMC) - Elegoo Image Cleanser Script - Not Advised"
    echo "  armbian_resize              Resize Active Armbian Partition (for eMMC > 8GB)"
    echo ""
}

# Function to print the main menu
print_menu() {
    clear_screen
    echo -e "\033[0;33m$OPENNEPT4UNE_ART\033[0m"
    echo "======================================"
    echo "Welcome to OpenNept4une"
    echo "======================================"
    echo "1) Install/Update latest OpenNept4une Printer.cfg + other configs"
    echo ""
    echo "2) WiFi Config"
    echo ""
    echo "3) Enable USB Storage AutoMount"
    echo ""
    echo "4) Update MCU & (Virtual) MCU RPi Firmware"
    echo ""
    echo "5) Install/Update Touch-Screen Display Service (BETA)"
    echo ""
    echo "6) Advanced / More"
    echo ""
    echo "7) Update repository"
    echo ""
    echo "8) Exit"
    echo "======================================"
}

if [ -z "$1" ];
then
    run_fixes
    update_repo
    # Main menu loop
    while true; do
        print_menu
        read -p "Enter your choice: " choice
        case $choice in
            1)
                install_printer_cfg
                ;;
            2)
                wifi_config
                ;;
            3)
                usb_auto_mount
                ;;
            4)
                update_mcu_rpi_fw
                ;;
            5)
                install_screen_service
                ;;
            6)
                advanced_more
                ;;
            7)
                update_repo
                ;;
            8)
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo "Invalid choice. Please try again."
                ;;
        esac
    done
else
    TEMP=$(getopt -o yh --long yes,help,printer_model:,motor_current:,pcb_version: \
                -n 'OpenNept4une.sh' -- "$@")
    if [ $? != 0 ] ; then exit 1 ; fi
    eval set -- "$TEMP"

    while true; do
        case "$1" in
            --printer_model ) PRINTER_MODEL="$2"; shift 2 ;;
            --motor_current ) MOTOR_CURRENT="$2"; shift 2 ;;
            --pcb_version ) PCB_VERSION="$2"; shift 2 ;;
            -y|--yes ) SAY_YES=true; shift ;;
            -h|--help ) print_help; exit 0 ;;
            * ) break ;;
        esac
    done

    run_fixes

    COMMAND=$1;

    case $COMMAND in
        install_printer_cfg ) install_printer_cfg ;;
        wifi_config ) wifi_config ;;
        usb_auto_mount ) usb_auto_mount ;;
        update_mcu_rpi_fw|update_mcu ) update_mcu_rpi_fw ;;
        install_screen_service ) install_screen_service ;;
        update_repo ) update_repo ;;
        android_rules ) android_rules ;;
        crowsnest_fix ) crowsnest_fix ;;
        base_image_config ) base_image_config ;;
        de_elegoo_image_cleanser ) de_elegoo_image_cleanser ;;
        armbian_resize ) armbian_resize ;;
        * ) echo "Invalid command. Please try again." ;;
    esac
fi