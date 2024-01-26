#!/bin/bash

# Prompt the user to select the MCU for updating
echo ""
echo "Choose the MCU(s) to update:"
echo ""
select mcu_choice in "STM32" "Virtual RPi" "Both" "Cancel"; do
    case $mcu_choice in
        STM32 ) echo "Updating STM32 MCU..."; break;;
        Virtual\ RPi ) echo "Updating Virtual RPi MCU..."; break;;
        Both ) echo "Starting update process for both STM32 and Virtual RPi MCUs..."; break;;
        Cancel ) echo "Update canceled."; exit;;
    esac
done

# Update Klipper repository
cd ~/klipper/ && git pull origin master

# Update procedure for STM32 MCU
if [[ "$mcu_choice" == "STM32" ]] || [[ "$mcu_choice" == "Both" ]]; then
    make clean
    cp ~/OpenNept4une/mcu-firmware/mcu.config ~/klipper/.config
    make
    # Create the 'Firmware' directory if it doesn't exist
    mkdir -p ~/printer_data/config/Firmware

    # Remove old files in previous parent directory 
    rm ~/printer_data/config/X_4.bin
    rm ~/printer_data/config/elegoo_k1.bin
    
    cp ~/klipper/out/klipper.bin ~/printer_data/config/Firmware/X_4.bin
    cp ~/klipper/out/klipper.bin ~/printer_data/config/Firmware/elegoo_k1.bin
    
    # Display instructions for downloading the firmware
    ip_address=$(hostname -I | awk '{print $1}')
    echo ""
    echo -e "\nTo download firmware files:"
    echo "1. Visit: http://$ip_address/#/configure"
    echo "2. Click the Firmware folder in the left Config list"
    echo "3. Right click and Download 'X_4.bin' and 'elegoo_k1.bin' to a FAT32 formatted microSD card."
    echo ""
    echo -e "\nTo complete the update:"
    echo "1. After this script completes, power off the printer and insert the microSD card."
    echo "2. Power on and check the MCU version in Fluidd's system tab."
    echo "3. One of the '.bin' files on the microSD should be renamed to '.CUR' if the update was successful."
    echo ""
    echo -e "\nFor printers without external microSD slots:"
    echo "1. Remove the front 4 hex screws and bottom access panel."
    echo "2. Remove the 2 front panel mount screws from inside the PCB area."
    echo "3. Consider cutting a slot in the front panel for future ease."
    echo ""
    echo -e "\nHave you downloaded the bin files and are ready to continue? (y/n)"
    read continue_choice
    if [[ "$continue_choice" != "y" ]]; then
        echo ""
        echo "Power-off the machine and insert the microSD card."
        exit
    fi

    if [[ "$mcu_choice" == "Both" ]]; then
        echo ""
        echo "Proceeding with Virtual MCU RPi Update..."
        echo ""
    fi
fi

# Update procedure for Virtual RPi MCU
if [[ "$mcu_choice" == "Virtual RPi" ]] || [[ "$mcu_choice" == "Both" ]]; then
    sudo apt install -y python3-numpy python3-matplotlib libatlas-base-dev
    ~/klippy-env/bin/pip install -v numpy
    sudo cp ./scripts/klipper-mcu.service /etc/systemd/system/
    sudo systemctl enable klipper-mcu.service
    make clean
    cp ~/OpenNept4une/mcu-firmware/virtualmcu.config ~/klipper/.config
    sudo service klipper stop
    echo "kernel.sched_rt_runtime_us = -1" | sudo tee -a /etc/sysctl.d/10-disable-rt-group-limit.conf
    make flash
    echo ""
    echo "Virtual MCU update completed."
    echo ""

    # System reboot countdown for Virtual RPi MCU update
    countdown=20
    echo "Rebooting in $countdown seconds..."
    while [ $countdown -gt 0 ]; do
        echo "$countdown..."
        sleep 1
        countdown=$((countdown-1))
    done
    sudo reboot
fi
