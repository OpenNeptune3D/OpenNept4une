#!/bin/bash

# Stop the Klipper service
echo "Stopping the Klipper service..."
sudo service klipper stop

# Short delay to ensure the service has stopped
sleep 1

# Enable bootloader mode
echo "Enabling bootloader mode..."
sudo gpioset gpiochip1 15=0
sleep 0.5
sudo gpioset gpiochip1 14=1
sleep 0.5
sudo gpioset gpiochip1 15=1
sleep 0.5
sudo gpioset gpiochip1 14=0

# Prompt for backup
echo "Do you want to create a firmware backup? (y/n)"
read -r create_backup

if [[ $create_backup == "y" ]]; then
    BACKUP_FILE=~/firmware-bak.bin
    if [ -f "$BACKUP_FILE" ]; then
        echo "Backup file $BACKUP_FILE already exists. Overwrite it? (y/n)"
        read -r overwrite_backup
        if [[ $overwrite_backup != "y" ]]; then
            echo "Enter new backup file name:"
            read -r new_backup_file
            BACKUP_FILE=~/${new_backup_file}
        fi
    fi
    echo "Backing up current firmware to $BACKUP_FILE..."
    stm32flash -r "$BACKUP_FILE" -g 0x0 /dev/ttyS0
else
    echo "Skipping backup."
fi

# Navigate to the Klipper directory and run make menuconfig
echo "Running make menuconfig in the Klipper directory..."
cd ~/klipper/
make menuconfig

# Compile the firmware after exiting menuconfig
echo "Compiling the firmware..."
make

# Enable bootloader mode again
echo "Enabling bootloader mode again..."
sudo gpioset gpiochip1 15=0
sleep 0.5
sudo gpioset gpiochip1 14=1
sleep 0.5
sudo gpioset gpiochip1 15=1
sleep 0.5
sudo gpioset gpiochip1 14=0

# Flash the new firmware
echo "Flashing new firmware to STM32F4..."
stm32flash -w /home/mks/klipper/out/klipper.bin -v -g 0x08008000 /dev/ttyS0

echo "Flashing complete"

# Starting the Klipper service
echo "Starting the Klipper service..."
sudo service klipper start
