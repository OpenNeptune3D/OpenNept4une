#!/bin/bash

# Define the base directory for mount points
base_mount_dir="/home/mks/printer_data/gcodes/usb"

# Create a new udev rule file
udev_rule_file="/etc/udev/rules.d/99-usb_automount.rules"

# Function to create a udev rule
create_udev_rule() {
    echo 'ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_USAGE}=="filesystem", ENV{ID_FS_LABEL}!="", RUN+="/usr/bin/systemd-mount --no-block --automount=yes --collect --mkdir --options=ro $env{DEVNAME} '$base_mount_dir/%E{ID_FS_LABEL}'"' > $udev_rule_file
    echo 'ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_USAGE}=="filesystem", ENV{ID_FS_LABEL}=="", RUN+="/usr/bin/systemd-mount --no-block --automount=yes --collect --mkdir --options=ro $env{DEVNAME} '$base_mount_dir/%E{ID_SERIAL}'"' >> $udev_rule_file
}

# Check if the script is run as root
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi

# Create the base mount directory if it doesn't exist
mkdir -p $base_mount_dir

# Create the udev rule
create_udev_rule

# Reload udev rules
udevadm control --reload-rules && udevadm trigger

echo "Udev rule for USB automount with read-only option is configured."
