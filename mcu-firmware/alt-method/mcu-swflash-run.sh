#!/bin/bash

# Stop the Klipper service
echo "Stopping the Klipper service..."
sudo service klipper stop

# Short delay to ensure the service has stopped
sleep .5

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
    # Enable bootloader mode
    echo "Enabling bootloader mode..."
    sudo gpioset -t0 -c gpiochip1 15=0
    sleep 0.5
    sudo gpioset -t0 -c gpiochip1 14=1
    sleep 0.5
    sudo gpioset -t0 -c gpiochip1 15=1
    sleep 0.5
    sudo gpioset -t0 -c gpiochip1 14=0
    echo "Backing up current firmware to $BACKUP_FILE..."
    stm32flash -r "$BACKUP_FILE" -g 0x0 /dev/ttyS0
else
    echo "Skipping backup."
fi

# Enable bootloader mode again
echo "Enabling bootloader mode..."
sudo gpioset -t0 -c gpiochip1 15=0
sleep 0.5
sudo gpioset -t0 -c gpiochip1 14=1
sleep 0.5
sudo gpioset -t0 -c gpiochip1 15=1
sleep 0.5
sudo gpioset -t0 -c gpiochip1 14=0

# Flash the new firmware
echo "Flashing new firmware to STM32..."
stm32flash -w ~/klipper/out/klipper.bin -v -S 0x08008000 -g 0x08000000 /dev/ttyS0

echo "Flashing complete"
gpioset -t0 -c gpiochip1 15=0; sleep 0.5; gpioset -t0 -c gpiochip1 15=1; sleep 1
# Starting the Klipper service
echo "Starting the Klipper service..."
sudo service klipper start
