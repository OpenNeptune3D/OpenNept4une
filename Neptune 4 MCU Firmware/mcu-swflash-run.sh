#!/bin/bash

# Navigate to the Klipper directory and run make menuconfig
echo "Running make menuconfig in the Klipper directory..."
cd ~/klipper/
make menuconfig

# Compile the firmware after exiting menuconfig
echo "Compiling the firmware..."
make

# Stop the Klipper service
echo "Stopping the Klipper service..."
sudo service klipper stop

# Short delay to ensure the service has stopped
sleep 1

# Toggling the BOOT and RESET GPIOs to enter bootloader mode
echo "Toggling BOOT and RESET GPIOs to enter bootloader mode..."
sudo gpioset gpiochip1 15=0
sleep 0.5
sudo gpioset gpiochip1 14=1
sleep 0.5
sudo gpioset gpiochip1 15=1
sleep 0.5
sudo gpioset gpiochip1 14=0

# Short delay to ensure the STM32F4 is ready
sleep 1

# Running stm32flash to write the firmware
echo "Flashing firmware to STM32F4..."
stm32flash -w /home/mks/klipper/out/klipper.bin -v -g 0x8008000 /dev/ttyS0

echo "Starting the Klipper service..."
sudo service klipper start

echo "Flashing complete"
