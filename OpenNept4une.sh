#!/bin/bash

# Check if the script has been run before and the system rebooted
REBOOT_FLAG="/home/mks/OpenNept4une/.opennept4une_rebooted"
sudo rm -f "$REBOOT_FLAG"

function clone_repo {
    local repo_url=$1
    local dest_dir=$2
    if [ ! -d "$dest_dir" ]; then
        git clone "$repo_url" "$dest_dir" || { echo "Error cloning $repo_url"; exit 1; }
    fi
}

function copy_file {
    local src=$1
    local dest=$2
    local use_sudo=${3:-false}

    if [ -f "$src" ]; then
        if [ "$use_sudo" = true ]; then
            sudo cp "$src" "$dest" || { echo "Error copying $src to $dest"; exit 1; }
        else
            cp "$src" "$dest" || { echo "Error copying $src to $dest"; exit 1; }
        fi
    else
        echo "Error: File $src not found."
    fi
}

if [ -f "$REBOOT_FLAG" ]; then
    sudo rm -f "$REBOOT_FLAG"
    sudo rm -f /usr/local/bin/set_gpio.sh
    sudo nmtui
    clone_repo "https://github.com/kyleisah/Klipper-Adaptive-Meshing-Purging.git" "/home/mks/Klipper-Adaptive-Meshing-Purging"
    # Create a symbolic link if not exists
    [ ! -L "/home/mks/printer_data/config/KAMP" ] && ln -s /home/mks/Klipper-Adaptive-Meshing-Purging/Configuration /home/mks/printer_data/config/KAMP
    clone_repo "https://github.com/dw-0/kiauh.git" "/home/mks/kiauh"
    sync
    /home/mks/kiauh/kiauh.sh
else 
    echo "Reboot flag not found, executing else branch"
    sudo usermod -aG gpio,spiusers mks

    PRINTER_CFG_DEST="/home/mks/printer_data/config"
    DTB_DEST="/boot/dtb/rockchip/rk3328-roc-cc.dtb"
    DATABASE_DEST="/home/mks/printer_data/database"

    mkdir -p "$PRINTER_CFG_DEST" "$DATABASE_DEST"

    declare -a CONF_FILES=("KAMP_Settings.cfg" "mainsail.cfg" "moonraker.conf" "adxl.cfg" "crowsnest.conf")
    for conf_file in "${CONF_FILES[@]}"; do
        copy_file "/home/mks/OpenNept4une/img-config/printer-data/$conf_file" "$PRINTER_CFG_DEST/$conf_file"
    done

    copy_file "/home/mks/OpenNept4une/img-config/printer-data/data.mdb" "$DATABASE_DEST/data.mdb"

    echo "Please select your machine type:"
    echo "1) Neptune4 (n4)"
    echo "2) Neptune4 Pro (n4pro)"
    echo "3) Neptune4 Plus (n4plus)"
    echo "4) Neptune4 Max (n4max)"
    read -p "Enter your choice (1-4): " MACHINE_TYPE

    PRINTER_CFG_SOURCE=""
    DTB_SOURCE=""

    case $MACHINE_TYPE in
        1 | 2) # Neptune4 (n4) or Neptune4 Pro (n4pro)
            read -p "Are you using a 0.8 or 1.2 stepper motor current? (Enter 0.8 or 1.2): " MOTOR_CURRENT
            read -p "Do you have PCB version 1.0 or 1.1? (Enter 1.0 or 1.1): " PCB_VERSION
            if [ "$MACHINE_TYPE" == "1" ]; then
                PRINTER_CFG_SOURCE="printer-confs/n4/n4-${MOTOR_CURRENT}-printer.cfg"
                DTB_SOURCE="dtb/n4-n4pro-v${PCB_VERSION}/rk3328-roc-cc.dtb"
            elif [ "$MACHINE_TYPE" == "2" ]; then
                PRINTER_CFG_SOURCE="printer-confs/n4pro/n4pro-${MOTOR_CURRENT}-printer.cfg"
                DTB_SOURCE="dtb/n4-n4pro-v${PCB_VERSION}/rk3328-roc-cc.dtb"
            fi
            ;;
        3) # Neptune4 Plus
            PRINTER_CFG_SOURCE="printer-confs/n4plus/n4plus-printer.cfg"
            DTB_SOURCE="dtb/n4plus-n4max-v1.1-2.0/rk3328-roc-cc.dtb"
            ;;
        4) # Neptune4 Max
            PRINTER_CFG_SOURCE="printer-confs/n4max/n4max-printer.cfg"
            DTB_SOURCE="dtb/n4plus-n4max-v1.1-2.0/rk3328-roc-cc.dtb"
            ;;
    esac

    if [ -n "$PRINTER_CFG_SOURCE" ]; then
        copy_file "/home/mks/OpenNept4une/$PRINTER_CFG_SOURCE" "$PRINTER_CFG_DEST/printer.cfg"
    else
        echo "Error: Invalid printer selection or PCB version."
    fi

    if [ -n "$DTB_SOURCE" ]; then
    	copy_file "/home/mks/OpenNept4une/$DTB_SOURCE" "$DTB_DEST" true
    else
        echo "Error: Invalid DTB file selection."
    fi
    
    sudo rm -f /usr/local/bin/set_gpio.sh
    echo "The system needs to be rebooted to continue. Reboot now? (y/n)"
    read -p "Enter your choice (highly advised): " REBOOT_CHOICE
    if [ "$REBOOT_CHOICE" == "y" ]; then
        touch "$REBOOT_FLAG"
        echo "System will reboot now."
        sudo reboot
    fi
fi
