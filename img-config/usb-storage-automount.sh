#!/bin/bash

# Create the base mount directory if it doesn't exist
mkdir -p ~/home/mks/printer_data/gcodes/USB

sudo -u mks echo 'ACTION=="add", SUBSYSTEMS=="usb", SUBSYSTEM=="block", KERNEL=="sd*1", ENV{ID_FS_USAGE}=="filesystem", RUN{program}+="/usr/bin/systemd-mount --no-block --automount=yes --collect --options ro,nofail $devnode /home/mks/printer_data/gcodes/USB"' | sudo tee -a /etc/udev/rules.d/99-usb_automount.rules

# Reload udev rules
sudo udevadm control --reload-rules && sudo udevadm trigger

echo "Udev rule for USB automount with read-only option is configured."
