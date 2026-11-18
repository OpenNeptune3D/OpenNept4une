#!/bin/bash

# Paths
KLIPPER_DIR="${HOME}/klipper"
FIRMWARE_DIR="${HOME}/printer_data/config/Firmware"
MCU_SWFLASH_ALT="${HOME}/OpenNept4une/mcu-firmware/alt-method/mcu-swflash-run.sh"
USB_TOOLHEAD_CONFIG="${HOME}/OpenNept4une/mcu-firmware/usb_c_toolhead.config"
USB_TOOLHEAD_SERIAL_GLOB="/dev/serial/by-id/usb-Klipper_stm32f103xe_*"
# MKS bootloader on the toolhead, present for about 10 s after power-up (OpenNept4une#417)
USB_TOOLHEAD_BOOT_GLOB="/dev/serial/by-id/usb-MKS_DRIVER_BOOT_*"
USB_TOOLHEAD_BOOT_VIDPID="1d50:018a"
USB_TOOLHEAD_MAX_SIZE=$((96 * 1024))   # application region 0x08008000-0x08020000
TOOLHEAD_POWER_HELPER="/usr/local/sbin/opennept4une-toolhead-power"
N4FLASH_SRC="${HOME}/OpenNept4une/mcu-firmware/n4flash/n4flash.c"
N4FLASH_BIN="${HOME}/.local/lib/opennept4une/n4flash"

# Helper to apply a minimal config and expand it
apply_minimal_config() {
    local config_file="$1"
    cd "$KLIPPER_DIR" || exit 1
    make clean
    rm -rf out
    cp "$config_file" .config
    make olddefconfig
}

print_usb_toolhead_id_hint() {
    local toolhead_id

    echo "Waiting for USB-C toolhead to reconnect..."
    for _ in {1..30}; do
        toolhead_id=$(compgen -G "$USB_TOOLHEAD_SERIAL_GLOB" | head -n 1)
        if [[ -n "$toolhead_id" ]]; then
            echo ""
            echo "USB-C toolhead serial ID:"
            echo "$toolhead_id"
            echo ""
            if python3 "${HOME}/OpenNept4une/printer-confs/generate_conf.py" --write-mcu-id; then
                echo "Updated ${HOME}/printer_data/config/MCU_ID.cfg"
            else
                echo "Failed to update MCU_ID.cfg automatically. Add/update it manually:"
                echo ""
                echo "${HOME}/printer_data/config/MCU_ID.cfg"
                echo ""
                echo "[mcu THR]"
                echo "serial: $toolhead_id"
                echo "restart_method: command"
            fi
            echo ""
            return 0
        fi
        sleep 1
    done

    echo ""
    echo "USB-C toolhead did not reconnect as a Klipper serial device yet."
    echo "After reboot, check with:"
    echo "ls /dev/serial/by-id/usb-Klipper_stm32f103xe_*"
    echo "Then run OpenNept4une.sh -> Install/Update printer.cfg to regenerate MCU_ID.cfg."
    echo ""
    return 1
}

# Build n4flash from the vendored source when missing or older than the source
ensure_n4flash() {
    [[ -x "$N4FLASH_BIN" && "$N4FLASH_BIN" -nt "$N4FLASH_SRC" ]] && return 0
    echo "Building n4flash..."
    mkdir -p "$(dirname "$N4FLASH_BIN")" && cc -O2 -Wall -o "$N4FLASH_BIN" "$N4FLASH_SRC"
}

# Power-cycle the toolhead so it starts in its bootloader, and print the bootloader's
# serial path. It stays there about 10 s before booting the application.
enter_usb_toolhead_bootloader() {
    local boot=()
    sudo "$TOOLHEAD_POWER_HELPER" cycle 0.5 >&2 || return 1
    for _ in {1..20}; do
        mapfile -t boot < <(compgen -G "$USB_TOOLHEAD_BOOT_GLOB")
        if (( ${#boot[@]} > 1 )); then
            echo "More than one toolhead bootloader found: ${boot[*]}" >&2
            return 1
        fi
        if (( ${#boot[@]} == 1 )) && lsusb -d "$USB_TOOLHEAD_BOOT_VIDPID" >/dev/null 2>&1; then
            echo "${boot[0]}"
            return 0
        fi
        sleep 0.5
    done
    return 1
}

# Build Klipper for the USB-C toolhead and flash it through the MKS bootloader with
# n4flash. Leaves Klipper stopped when updating "All".
update_usb_toolhead() {
    local firmware="$KLIPPER_DIR/out/klipper.bin" size boot_dev

    if [[ ! -x "$TOOLHEAD_POWER_HELPER" ]]; then
        echo "Skipping the USB-C toolhead: this printer is not set to the USB-C printhead,"
        echo "so its power (and bootloader entry) is not under OpenNept4une's control."
        echo "If it has one, select it in OpenNept4une.sh -> Install/Update printer.cfg first."
        sleep 5
        return 0
    fi

    echo "Building USB-C toolhead firmware..."
    apply_minimal_config "$USB_TOOLHEAD_CONFIG"
    # The toolhead MCU is a GD32F303 (Cortex-M4) behind an STM32F103 configuration.
    # Klipper builds STM32F103 for Cortex-M3; the second -mcpu wins. This matches the
    # build tested on real toolheads.
    make 'MCU_UPPER=STM32F103xE -mcpu=cortex-m4' || {
        echo "Failed to build USB-C toolhead firmware."
        exit 1
    }
    size=$(stat -c %s "$firmware") || exit 1
    if (( size > USB_TOOLHEAD_MAX_SIZE )); then
        echo "Toolhead firmware is ${size} bytes; the toolhead only has room for ${USB_TOOLHEAD_MAX_SIZE}."
        exit 1
    fi
    ensure_n4flash || {
        echo "Failed to build n4flash (needs a C compiler: sudo apt install build-essential)."
        exit 1
    }

    echo "Stopping Klipper..."
    sudo service klipper stop || true
    sleep 2

    echo "Power-cycling the USB-C toolhead into its bootloader..."
    if ! boot_dev=$(enter_usb_toolhead_bootloader); then
        echo "USB-C toolhead bootloader ($USB_TOOLHEAD_BOOT_VIDPID) not detected. Skipping flash."
        [[ "$mcu_choice" != "All" ]] && { sudo service klipper start || true; }
        sleep 5
        return 0
    fi

    echo "Flashing USB-C toolhead via $boot_dev. Do not power off the printer."
    if ! "$N4FLASH_BIN" "$firmware" "$boot_dev"; then
        echo "Failed to flash the USB-C toolhead. It stays in its bootloader;"
        echo "run the USB-C Toolhead update again."
        sudo service klipper start || true
        exit 1
    fi

    # n4flash reports success before the bootloader confirms; the application
    # re-enumerating is the real confirmation.
    if print_usb_toolhead_id_hint; then
        echo "USB-C toolhead update completed."
    fi
    [[ "$mcu_choice" != "All" ]] && { sudo service klipper start || true; }
    sleep 2
}

# Get current git branch from $KLIPPER_DIR
cd "$KLIPPER_DIR" || exit 1
current_branch=$(git rev-parse --abbrev-ref HEAD)

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
    select mcu_choice in "STM32" "USB-C Toolhead" "Virtual RPi" "Pico-based USB Accelerometer" "All" "Cancel"; do
        case $mcu_choice in
            STM32 ) break;;
            USB-C\ Toolhead ) break;;
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

if [[ $pull_exit -ne 0 ]]; then
    echo -e "\n❌ Git pull failed for '$current_branch'!"
    echo "$pull_output"
    sleep 20
    exit 1
fi

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

### USB-C TOOLHEAD MCU ###
if [[ "$mcu_choice" == "USB-C Toolhead" || "$mcu_choice" == "All" ]]; then
    clear
    echo "Proceeding with USB-C Toolhead MCU Update..."
    update_usb_toolhead
fi

### PICO USB ACCELEROMETER ###
pico_skipped=false
if [[ "$mcu_choice" == "Pico-based USB Accelerometer" || "$mcu_choice" == "All" ]]; then
    clear
    echo "Proceeding with Pico-based USB Accelerometer Update..."

    pico_bootloader=$(lsusb | grep -o '2e8a:000[f3]' 2>/dev/null)
    while true; do
        pico_bootloader=$(lsusb | grep -o '2e8a:000[f3]' 2>/dev/null)
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
        for pkg in python3-numpy python3-matplotlib libatlas3-base libopenblas-dev; do
            if ! sudo apt install -y "$pkg" 2>&1 | grep -v "already installed"; then
                echo "Warning: failed to install $pkg"
            fi
        done

        echo "Installing numpy in Klipper environment..."
        ~/klippy-env/bin/pip install numpy

        apply_minimal_config "${HOME}/OpenNept4une/mcu-firmware/pico_usb.config"
        make
        make flash FLASH_DEVICE=$pico_bootloader

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
    for pkg in python3-numpy python3-matplotlib libatlas3-base libopenblas-dev; do
        echo "Installing $pkg..."
        if ! sudo apt install -y "$pkg"; then
            echo "Warning: Failed to install $pkg." >&2
        fi
    done
    echo "Package installation complete."

    echo "Installing numpy in Klipper environment..."
    ~/klippy-env/bin/pip install numpy || { echo "Numpy installation failed, continuing..."; }

    echo "Copying klipper-mcu.service..."
    sudo cp ./scripts/klipper-mcu.service /etc/systemd/system/ || { echo "Failed to copy service file"; exit 1; }

    echo "Enabling klipper-mcu.service..."
    sudo systemctl enable klipper-mcu.service || { echo "Failed to enable service"; exit 1; }

    echo "Stopping klipper service..."
    sudo service klipper stop || true

    if [[ -f /boot/.OpenNept4une.txt ]]; then
        if grep -iq "mks" /boot/.OpenNept4une.txt; then
            echo "Skipping kernel patch for MKS systems..."
        elif grep -Eqi "dec 11|oct 12" /boot/.OpenNept4une.txt; then
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
