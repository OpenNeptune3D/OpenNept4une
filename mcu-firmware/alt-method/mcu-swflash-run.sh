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
    sudo gpioset gpiochip1 15=0
    sleep 0.5
    sudo gpioset gpiochip1 14=1
    sleep 0.5
    sudo gpioset gpiochip1 15=1
    sleep 0.5
    sudo gpioset gpiochip1 14=0
    echo "Backing up current firmware to $BACKUP_FILE..."
    stm32flash -r "$BACKUP_FILE" -g 0x0 /dev/ttyS0
else
    echo "Skipping backup."
fi

# Check if klipper.bin exists in the current directory
KLIPPER_BIN=./klipper.bin
if [ -f "$KLIPPER_BIN" ]; then
    echo "klipper.bin file exists in the current directory. Do you want to flash it? (y/n)"
    read -r flash_existing_bin
    if [[ $flash_existing_bin == "y" ]]; then
        # Flash the existing firmware
	# Enable bootloader mode
	echo "Enabling bootloader mode..."
	sudo gpioset gpiochip1 15=0
	sleep 0.5
	sudo gpioset gpiochip1 14=1
	sleep 0.5
	sudo gpioset gpiochip1 15=1
	sleep 0.5
	sudo gpioset gpiochip1 14=0        

	echo "Flashing existing firmware..."
        stm32flash -w "$KLIPPER_BIN" -v  /dev/ttyS0
        echo "Flashing complete"
	gpioset gpiochip1 15=0; sleep 0.5; gpioset gpiochip1 15=1; sleep 1  
        # Starting the Klipper service
        echo "Starting the Klipper service..."
        sudo service klipper start
        exit 0
    fi
fi

# Navigate to the Klipper directory and run make menuconfig
echo "Running make menuconfig in the Klipper directory..."
cd ~/klipper/
make menuconfig

# Enable bootloader mode again
echo "Enabling bootloader mode..."
sudo gpioset gpiochip1 15=0
sleep 0.5
sudo gpioset gpiochip1 14=1
sleep 0.5
sudo gpioset gpiochip1 15=1
sleep 0.5
sudo gpioset gpiochip1 14=0

# Compile the firmware after exiting menuconfig
echo "Compiling the firmware..."
make clean
make
# Flash the new firmware
echo "Flashing new firmware to STM32F4..."
stm32flash -w ~/klipper/out/klipper.bin -v -S 0x08008000 -g 0x08000000 /dev/ttyS0

echo "Flashing complete"
gpioset gpiochip1 15=0; sleep 0.5; gpioset gpiochip1 15=1; sleep 1
# Starting the Klipper service
echo "Starting the Klipper service..."
sudo service klipper start
