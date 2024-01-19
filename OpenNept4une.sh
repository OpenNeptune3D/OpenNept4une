#!/bin/bash

# Path to the script and other resources
SCRIPT="/home/mks/OpenNept4une/OpenNept4une.sh"
DISPLAY_SERVICE_INSTALLER="/home/mks/OpenNept4une/display/display-service-installer.sh"
MCU_RPI_INSTALLER="/home/mks/OpenNept4une/img-config/rpi-mcu-install.sh"
USB_STORAGE_AUTOMOUNT="/home/mks/OpenNept4une/img-config/usb-storage-automount.sh"
ANDROID_RULE_INSTALLER="/home/mks/OpenNept4une/img-config/adb-automount.sh"
CROWSNEST_FIX_INSTALLER="/home/mks/OpenNept4une/img-config/crowsnest-lag-fix.sh"
BASE_IMAGE_INSTALLER="/home/mks/OpenNept4une/img-config/base_image_configuration.sh"
DE_ELEGOO_IMAGE_CLEANSER="/home/mks/OpenNept4une/img-config/de_elegoo_cleanser.sh"
FLAG_FILE="/boot/.OpenNept4une.txt"

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
    repo_dir="/home/mks/OpenNept4une"
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
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Updating repository..."
            git reset --hard
            git clean -fd
            # Pull the updates
            git pull origin main --force
            chmod +x "$SCRIPT"
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

update_repo

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
    echo "3) Base Compiled Image Config (Dont use on release images)"
    echo ""
    echo "4) Method 2 - Elegoo Image Cleanser Script - Not Advised"
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
    echo "Do you want to install the android ADB rules? (may fix klipperscreen issues)"
    read -p "Enter 'y' to install, any other key to skip: " install_android_rules

    if [[ $install_android_rules == "y" ]]; then
        echo "Running ADB Rule Installer..."
        if [ -f "$ANDROID_RULE_INSTALLER" ]; then
            chmod +x "$ANDROID_RULE_INSTALLER"
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
    echo "Do you want to install the crowsnest fps fix?"
    read -p "Enter 'y' to install, any other key to skip: " install_crowsnest_fix

    if [[ $install_crowsnest_fix == "y" ]]; then
        echo "Running crowsnest Fix Installer..."
        if [ -f "$CROWSNEST_FIX_INSTALLER" ]; then
            chmod +x "$CROWSNEST_FIX_INSTALLER"
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
    echo "Do you want to configure a base/fresh armbian image that you compiled?"
    read -p "Enter 'y' to install, any other key to skip: " install_base_image_config

    if [[ $install_base_image_config == "y" ]]; then
        echo "Running base/fresh image Installer..."
        if [ -f "$BASE_IMAGE_INSTALLER" ]; then
            chmod +x "$BASE_IMAGE_INSTALLER"
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
    read -p "Enter 'y' to install, any other key to skip: " install_de_elegoo_image_cleanser

    if [[ $install_de_elegoo_image_cleanser == "y" ]]; then
        echo "Running De-Elegoo Script..."
        if [ -f "$DE_ELEGOO_IMAGE_CLEANSER" ]; then
            chmod +x "$DE_ELEGOO_IMAGE_CLEANSER"
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
    read -p "Enter 'y' to run, any other key to skip: " run_armbian_resize

    if [[ $run_armbian_resize == "y" ]]; then
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
    echo "Do you want to install the (WIP) Touch-Screen implementation? (barely functional, frequent updates)"
    read -p "Enter 'y' to install, any other key to skip: " install_screen

    if [[ $install_screen == "y" ]]; then
        echo "Installing Touch-Screen Service..."
        if [ -f "$DISPLAY_SERVICE_INSTALLER" ]; then
            sudo rm -rf /home/mks/OpenNept4une/display/venv
            chmod +x "$DISPLAY_SERVICE_INSTALLER"
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
    echo "Do you want to update the Virtual MCU rpi (responsible for ADXL SPI & LED control only)"
    read -p "Enter 'y' to install, any other key to skip: " install_mcu_rpi

    if [[ $install_mcu_rpi == "y" ]]; then
        echo "Running MCU rpi Installer..."
        if [ -f "$MCU_RPI_INSTALLER" ]; then
            chmod +x "$MCU_RPI_INSTALLER"
            "$MCU_RPI_INSTALLER"
        else
            echo "Error: Virtual MCU installer script not found."
        fi
        echo "======================================"
    fi
}

usb_auto_mount() {
    clear_screen
    echo -e "\033[0;33m$OPENNEPT4UNE_ART\033[0m"
    echo "======================================"
    echo "Do you want to auto mount USB drives? (Folder will mount as 'USB' in fluid 'Jobs' Tab)"
    read -p "Enter 'y' to install, any other key to skip: " install_usb_auto_mount

    if [[ $install_usb_auto_mount == "y" ]]; then
        echo "Running USB Auto Mount Installer..."
        if [ -f "$USB_STORAGE_AUTOMOUNT" ]; then
            chmod +x "$USB_STORAGE_AUTOMOUNT"
            "$USB_STORAGE_AUTOMOUNT"
        else
            echo "Error: USB Auto Mount installer script not found."
        fi
        echo "======================================"
    fi
}

# Function to copy files with error handling
copy_file() {
    local base_path="/home/mks/OpenNept4une"
    local src="$base_path/$1"
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
        echo "Backup of 'printer.cfg' created as 'backup-printer.cfg.bak'."
        sleep 5
    fi
    
    if [[ -n "$PRINTER_CFG_SOURCE" ]]; then
        copy_file "$PRINTER_CFG_SOURCE" "$PRINTER_CFG_DEST/printer.cfg" false
    else
        echo "Error: Invalid printer configuration file."
        return 1
    fi
    
    if [[ -n "$DTB_SOURCE" ]]; then
        read -p "Do you wish to update the DTB file? First Run on Git Image MUST select Yes, others skip (y/n) " -n 1 -r
        echo

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # New check for the string "mks" in /boot/.OpenNept4une.txt
            if grep -q "mks" /boot/.OpenNept4une.txt; then
                copy_file "$DTB_SOURCE" "/boot/dtb-5.16.20-rockchip64/rockchip/rk3328-roc-cc.dtb" true
                copy_file "$DTB_SOURCE" "$DTB_DEST" true
            else
                copy_file "$DTB_SOURCE" "$DTB_DEST" true
            fi
        else
            echo "Skipping DTB file update."
        fi
    else
        echo "Error: Invalid DTB file selection."
        return 1
    fi
    
    # User prompt for installing KAMP/moonraker and fluidd GUI configuration
    echo "Do you wish to install the latest KAMP/moonraker/fluiddGUI configurations? (yes/no)"
    read -p "If this is a first-time install, it is recommended. If just updating printer.cfg & you have custom KAMP configurations, it is best to skip: " user_choice

    if [[ "$user_choice" == "yes" ]]; then
        # Commands to install the latest configurations
        echo "Installing latest configurations..."
        cp -r /home/mks/OpenNept4une/img-config/printer-data/* /home/mks/printer_data/config/
        mv /home/mks/printer_data/config/data.mdb /home/mks/printer_data/database/data.mdb
    else
        echo "Skipping the installation of latest configurations."
    fi
}
    
install_printer_cfg() {
    clear_screen
    echo -e "\033[0;33m$OPENNEPT4UNE_ART\033[0m"
    echo "Please select your machine type:"
    echo "1) Neptune4"
    echo "2) Neptune4 Pro"
    echo "3) Neptune4 Plus"
    echo "4) Neptune4 Max"
    read -p "Enter your choice (1-4): " MACHINE_TYPE

    PRINTER_CFG_DEST="/home/mks/printer_data/config"
    DTB_DEST="/boot/dtb/rockchip/rk3328-roc-cc.dtb"
    DATABASE_DEST="/home/mks/printer_data/database"
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
        read -p "Enter stepper motor current (0.8 or 1.2): " MOTOR_CURRENT
        if [[ "$MOTOR_CURRENT" != "0.8" && "$MOTOR_CURRENT" != "1.2" ]]; then
            echo "Invalid motor current selection. Please enter 0.8 or 1.2."
            stepper_motor_current
        fi
    }

    pcb_version() {
        read -p "Enter PCB Version (1.0 or 1.1): " PCB_VERSION
        if [[ "$PCB_VERSION" != "1.0" && "$PCB_VERSION" != "1.1" ]]; then
            echo "Invalid PCB selection. Please enter 1.0 or 1.1."
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
            PRINTER_CFG_SOURCE="printer-confs/n4/n4-${MOTOR_CURRENT}-printer.cfg"
            DTB_SOURCE="dtb/n4-n4pro-v${PCB_VERSION}/rk3328-roc-cc.dtb"
            FLAG_LINE="N4-${MOTOR_CURRENT}A-v${PCB_VERSION}"
            ;;
        2)
            clear_screen
            echo -e "\033[0;33m$OPENNEPT4UNE_ART\033[0m"
            echo "Configuring for Neptune4 Pro..."
            stepper_motor_current
            pcb_version
            PRINTER_CFG_SOURCE="printer-confs/n4pro/n4pro-${MOTOR_CURRENT}-printer.cfg"
            DTB_SOURCE="dtb/n4-n4pro-v${PCB_VERSION}/rk3328-roc-cc.dtb"
            FLAG_LINE="N4Pro-${MOTOR_CURRENT}A-v${PCB_VERSION}"
            ;;
        3)
            clear_screen
            echo -e "\033[0;33m$OPENNEPT4UNE_ART\033[0m"
            echo "Configuring for Neptune4 Plus..."
            PRINTER_CFG_SOURCE="printer-confs/n4plus/n4plus-printer.cfg"
            DTB_SOURCE="dtb/n4plus-n4max-v1.1-2.0/rk3328-roc-cc.dtb"
            FLAG_LINE="N4Plus"
            ;;
        4)
            clear_screen
            echo -e "\033[0;33m$OPENNEPT4UNE_ART\033[0m"
            echo "Configuring for Neptune4 Max..."
            PRINTER_CFG_SOURCE="configs/neptune4max/printer.cfg"
            DTB_SOURCE="dtb/n4plus-n4max-v1.1-2.0/rk3328-roc-cc.dtb"
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
    echo "The system needs to be rebooted to continue. Reboot now? (y/n)"
    read -p "Enter your choice (highly advised): " REBOOT_CHOICE
    if [[ "$REBOOT_CHOICE" == "y" ]]; then
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

# Function to print the main menu
print_menu() {
    clear_screen
    echo -e "\033[0;33m$OPENNEPT4UNE_ART\033[0m"
    echo "======================================"
    echo "Welcome to OpenNept4une"
    echo "======================================"
    echo "1) Install latest OpenNept4une Printer.cfg"
    echo ""
    echo "2) WiFi Config"
    echo ""
    echo "3) Enable USB Storage AutoMount"
    echo ""
    echo "4) Update (Virtual) MCU rpi Firmware"
    echo ""
    echo "5) Install (WIP) Touch Screen Implementation"
    echo ""
    echo "6) Advanced / More"
    echo ""
    echo "7) Update repository"
    echo ""
    echo "8) Exit"
    echo "======================================"
}

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
