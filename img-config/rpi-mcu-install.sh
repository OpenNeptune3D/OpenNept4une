#!/bin/bash

# Paths
KLIPPER_DIR="${HOME}/klipper"
FIRMWARE_DIR="${HOME}/printer_data/config/Firmware"
MCU_SWFLASH_ALT="${HOME}/OpenNept4une/mcu-firmware/alt-method/mcu-swflash-run.sh"
USB_TOOLHEAD_CONFIG="${HOME}/OpenNept4une/mcu-firmware/usb_c_toolhead.config"
USB_TOOLHEAD_SERIAL_GLOB="/dev/serial/by-id/usb-Klipper_stm32f103xe_*"
USB_TOOLHEAD_HID_VIDPID="1209:BEBA"

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
}

# Request USB serial bootloader entry via 1200 baud + DTR pulse
request_usb_bootloader() {
    local device="$1"

    python3 - "$device" <<'PY'
import sys, fcntl, termios, struct, time

dev = sys.argv[1]
with open(dev, "rb", buffering=0) as f:
    fd = f.fileno()
    fcntl.ioctl(fd, termios.TIOCMBIS, struct.pack("I", termios.TIOCM_DTR))
    attrs = termios.tcgetattr(fd)
    attrs[4] = termios.B1200
    attrs[5] = termios.B1200
    termios.tcsetattr(fd, termios.TCSANOW, attrs)
    time.sleep(0.2)
    fcntl.ioctl(fd, termios.TIOCMBIC, struct.pack("I", termios.TIOCM_DTR))
PY
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
toolhead_skipped=false
if [[ "$mcu_choice" == "USB-C Toolhead" || "$mcu_choice" == "All" ]]; then
    clear
    echo "Proceeding with USB-C Toolhead MCU Update..."

    while true; do
        toolhead_device=$(compgen -G "$USB_TOOLHEAD_SERIAL_GLOB" | head -n 1)

        if [[ -n "$toolhead_device" ]] || lsusb -d "$USB_TOOLHEAD_HID_VIDPID" >/dev/null 2>&1; then
            echo "USB-C toolhead detected. Proceeding..."
            break
        fi

        echo ""
        read -n 1 -p "USB-C toolhead not detected. Press any key to retry, or (s) to skip..." key
        echo ""
        if [[ $key == s || $key == S ]]; then
            toolhead_skipped=true
            clear
            break
        fi
    done

    if [[ "$toolhead_skipped" == false ]]; then
        echo "Building USB-C toolhead firmware..."
        apply_minimal_config "$USB_TOOLHEAD_CONFIG"
        make || {
            echo "Failed to build USB-C toolhead firmware."
            exit 1
        }

        echo "Stopping Klipper..."
        sudo service klipper stop || true
        sleep 2

        if ! lsusb -d "$USB_TOOLHEAD_HID_VIDPID" >/dev/null 2>&1; then
            if [[ -z "$toolhead_device" || ! -e "$toolhead_device" ]]; then
                echo "USB-C toolhead serial device disappeared. Skipping flash."
                if [[ "$mcu_choice" != "All" ]]; then
                    sudo service klipper start || true
                fi
                toolhead_skipped=true
            else
                echo "Requesting USB-C toolhead bootloader on $toolhead_device..."
                request_usb_bootloader "$toolhead_device"
            fi
        else
            echo "USB-C toolhead is already in HID bootloader mode."
        fi

        if [[ "$toolhead_skipped" == false ]]; then
            echo "Waiting for USB-C toolhead HID bootloader $USB_TOOLHEAD_HID_VIDPID..."
            bootloader_found=false
            for _ in {1..20}; do
                if lsusb -d "$USB_TOOLHEAD_HID_VIDPID" >/dev/null 2>&1; then
                    bootloader_found=true
                    break
                fi
                sleep 1
            done

            if [[ "$bootloader_found" != true ]]; then
                echo "USB-C toolhead bootloader not detected. Skipping flash."
                if [[ "$mcu_choice" != "All" ]]; then
                    sudo service klipper start || true
                fi
            else
                echo "Flashing USB-C toolhead..."
                make flash FLASH_DEVICE="$USB_TOOLHEAD_HID_VIDPID" || {
                    echo "Failed to flash USB-C toolhead."
                    sudo service klipper start || true
                    exit 1
                }

                echo "USB-C toolhead update completed."
                print_usb_toolhead_id_hint
                if [[ "$mcu_choice" != "All" ]]; then
                    sudo service klipper start || true
                fi
                sleep 2
            fi
        fi
    fi
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
