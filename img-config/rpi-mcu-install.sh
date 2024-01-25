#!/bin/bash

# Update package lists
sudo apt update

# Automatically confirm the installation of the required packages
sudo apt install -y python3-numpy python3-matplotlib libatlas-base-dev

# Install numpy using pip in a specific environment
~/klippy-env/bin/pip install -v numpy

# Copy klipper-mcu.service and enable the service
cd ~/klipper/ && git pull origin main
sudo cp ./scripts/klipper-mcu.service /etc/systemd/system/
sudo systemctl enable klipper-mcu.service

# Open menuconfig for user configuration
cd ~/klipper/
make clean
cp ~/OpenNept4une/mcu-firmware/virtualmcu.config ~/klipper/.config

# Stop, flash, and start klipper service
sudo service klipper stop
echo "kernel.sched_rt_runtime_us = -1" | sudo tee -a /etc/sysctl.d/10-disable-rt-group-limit.conf

make flash

echo "Script execution completed."

countdown=20

echo "System will reboot in $countdown seconds..."

# Countdown loop
while [ $countdown -gt 0 ]; do
    echo "$countdown..."
    sleep 1
    countdown=$((countdown-1))
done

echo "Rebooting now!"

# Reboot command (requires sudo privileges)
sudo reboot
