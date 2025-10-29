#!/bin/bash

# Paths
KLIPPER_DIR="${HOME}/klipper"
FIRMWARE_DIR="${HOME}/printer_data/config/Firmware"
MCU_SWFLASH_ALT="${HOME}/OpenNept4une/mcu-firmware/alt-method/mcu-swflash-run.sh"

# Helper to apply a minimal config and expand it
apply_minimal_config() {
    local config_file="$1"
    cd "$KLIPPER_DIR" || exit 1
    make clean
    cp "$config_file" .config
    make olddefconfig
}

# Get current git branch from $KLIPPER_DIR
cd "$KLIPPER_DIR" || exit 1
current_branch=$(git rev-parse --abbrev-ref HEAD)

# Check for detached HEAD status
if [[ "$current_branch" == "HEAD" ]]; then
    echo "Warning: Detached HEAD state detected!"
    sleep 30
    exit 1
fi

# Prompt user for MCU if not passed as argument
if [[ -z $1 ]]; then
    echo ""
    echo "Choose the MCU(s) to update:"
    echo ""
    select mcu_choice in "STM32" "Virtual RPi" "Pico-based USB Accelerometer" "All" "Cancel"; do
        case $mcu_choice in
            STM32 ) break;;
            Virtual\ RPi ) break;;
            Pico-based\ USB\ Accelerometer ) break;;
            All ) break;;
            Cancel ) echo "Update canceled."; exit;;
        esac
    done
else
    mcu_choice=$1
fi

# Update Klipper
cd "$KLIPPER_DIR" || exit 1
pull_output=$(git pull origin "$current_branch" 2>&1)
pull_exit=$?

# Check for git pull errors
if [[ $pull_exit -ne 0 ]]; then
    echo -e "\n❌ Git pull failed for '$current_branch'!"
    echo "$pull_output"
    sleep 20
    exit 1
fi

# Generate and show response message
if echo "$pull_output" | grep -iq "already up to date"; then
    echo -e "\nℹ️ Branch '$current_branch' is already up to date."
    sleep 5
else
    echo -e "\n✅ Git pull successful for '$current_branch':"
    echo "$pull_output"
    sleep 5
fi

### STM32 MCU UPDATE ###
if [[ "$mcu_choice" == "STM32" || "$mcu_choice" == "All" ]]; then
    clear
    echo "Proceeding with STM32 MCU Update..."

    apply_minimal_config "${HOME}/OpenNept4une/mcu-firmware/mcu.config"
    make

    if grep -q "/usr/local/bin/gpio_set.sh" "/etc/rc.local" 2>/dev/null; then
        echo "Detected MCU running the Alternative method! Running headless flash..."
        if [ -f "$MCU_SWFLASH_ALT" ]; then
            "$MCU_SWFLASH_ALT"
        else
            echo "Error: Alternate MCU flash script not found."
        fi
    else
        mkdir -p "$FIRMWARE_DIR"
        rm -f "$FIRMWARE_DIR/X_4.bin" "$FIRMWARE_DIR/elegoo_k1.bin"
        cp "$KLIPPER_DIR/out/klipper.bin" "$FIRMWARE_DIR/X_4.bin"
        cp "$KLIPPER_DIR/out/klipper.bin" "$FIRMWARE_DIR/elegoo_k1.bin"

        clear
        ip_address=$(hostname -I | awk '{print $1}')
        echo ""
        echo -e "\nTo download firmware files:"
        echo "1. Visit: http://$ip_address/#/configure"
        echo "2. Click the Firmware folder"
        echo "3. Download 'X_4.bin' and 'elegoo_k1.bin'"
        echo ""
        echo -e "\nTo complete the update:"
        echo "1. Power off the printer and insert the microSD card."
        echo "2. Power on the printer to flash."
        echo "3. Check Fluidd for version confirmation."
        echo ""
        echo -e "For internal MCUs, see the wiki:"
        echo "https://github.com/OpenNeptune3D/OpenNept4une/wiki"
        echo ""

        echo -e "\nHave you downloaded the bin files and are ready to continue? (y)"
        read continue_choice
        if [[ "$continue_choice" =~ ^[Yy]$ ]]; then
            if [[ "$mcu_choice" == "STM32" ]]; then
                echo "Power-off the machine and insert the microSD card."
                sleep 4
                exit
            fi
        fi
    fi
fi

### PICO USB ACCELEROMETER ###
pico_skipped=false
if [[ "$mcu_choice" == "Pico-based USB Accelerometer" || "$mcu_choice" == "All" ]]; then
    clear
    echo "Proceeding with Pico-based USB Accelerometer Update..."

    while true; do
        pico_bootloader=$(lsusb | grep '2e8a:0003' 2>/dev/null)
        if [[ -z "$pico_bootloader" ]]; then
            echo ""
            read -n 1 -p "Please put your Pico in bootloader mode. Press any key to retry, or (s) to skip..." key
            if [[ $key == s || $key == S ]]; then
                pico_skipped=true
                clear
                break
            fi
        else
            echo ""
            echo "Pico detected in bootloader mode. Proceeding..."
            break
        fi
    done

    if [[ "$pico_skipped" == false ]]; then
        echo "Installing Python packages for Pico..."
        for pkg in python3-numpy python3-matplotlib libatlas-base-dev libatlas3-base libopenblas-dev; do
            if ! sudo apt install -y "$pkg" 2>&1 | grep -v "already installed"; then
                echo "Warning: failed to install $pkg"
            fi
        done

        echo "Installing numpy in Klipper environment..."
        ~/klippy-env/bin/pip install -v numpy

        apply_minimal_config "${HOME}/OpenNept4une/mcu-firmware/pico_usb.config"
        make
        make flash FLASH_DEVICE=2e8a:0003

        echo ""
        echo "Pico-based Accelerometer update completed."
        sleep 2
    fi
fi

### VIRTUAL RPi MCU ###
if [[ "$mcu_choice" == "Virtual RPi" || "$mcu_choice" == "All" ]]; then
    clear
    echo "Proceeding with Virtual MCU RPi Update..."

    echo "Installing required packages (this may take a moment)..."
    for pkg in python3-numpy python3-matplotlib libatlas-base-dev libatlas3-base libopenblas-dev; do
        sudo apt install -y "$pkg" &>/dev/null || true
    done
    echo "Package installation complete."

    echo "Installing numpy in Klipper environment..."
    ~/klippy-env/bin/pip install -v numpy || { echo "Numpy installation failed, continuing..."; }

    echo "Copying klipper-mcu.service..."
    sudo cp ./scripts/klipper-mcu.service /etc/systemd/system/ || { echo "Failed to copy service file"; exit 1; }
    
    echo "Enabling klipper-mcu.service..."
    sudo systemctl enable klipper-mcu.service || { echo "Failed to enable service"; exit 1; }
    
    echo "Stopping klipper service..."
    sudo service klipper stop || true

    if [[ -f /boot/.OpenNept4une.txt ]]; then
        if grep -iq "mks" /boot/.OpenNept4une.txt; then
            echo "Skipping kernel patch for MKS systems..."
        elif grep -iq "dec 11" /boot/.OpenNept4une.txt; then 
            echo "Applying kernel patch..."
            echo "kernel.sched_rt_runtime_us = -1" | sudo tee -a /etc/sysctl.d/10-disable-rt-group-limit.conf
        fi
    fi

    echo "Applying Virtual MCU configuration..."
    apply_minimal_config "${HOME}/OpenNept4une/mcu-firmware/virtualmcu.config"
    
    echo "Flashing Virtual MCU..."
    make flash || { echo "Failed to flash Virtual MCU"; exit 1; }

    echo ""
    echo "Virtual MCU update completed."
    sleep 2

    countdown=20
    echo "Rebooting in $countdown seconds..."
    while [ $countdown -gt 0 ]; do
        echo "$countdown..."
        sleep 1
        countdown=$((countdown - 1))
    done
    sudo reboot
fi
