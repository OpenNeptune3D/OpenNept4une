#!/bin/bash

# Update package lists
sudo apt update

# Automatically confirm the installation of the required packages
sudo apt install -y python3-numpy python3-matplotlib libatlas-base-dev

# Install numpy using pip in a specific environment
~/klippy-env/bin/pip install -v numpy

# Copy klipper-mcu.service and enable the service
cd ~/klipper/
sudo cp ./scripts/klipper-mcu.service /etc/systemd/system/
sudo systemctl enable klipper-mcu.service

# Pause and provide instructions to the user
echo "Next, you will configure Klipper. In the menu, set 'Microcontroller Architecture' to 'Linux process,' then save and exit."
read -p "Press [Enter] key to open the menuconfig interface..."

# Open menuconfig for user configuration
cd ~/klipper/
make clean
make menuconfig

# The script pauses here allowing the user to make the necessary changes manually.

# Stop, flash, and start klipper service
sudo service klipper stop
make flash
sudo service klipper start

echo "Script execution completed."
