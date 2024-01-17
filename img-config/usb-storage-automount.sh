#!/bin/bash

# Base directories
MOUNT_DIR="/home/mks/printer_data/gcodes/USB"
SYMLINK_DIR="/home/mks/printer_data/gcodes"
RULE_FILE="/etc/udev/rules.d/99-usb_automount.rules"

create_symlink() {
    if [ -d "$MOUNT_DIR" ]; then
        # Find .gcode files and create symlinks
        find "$MOUNT_DIR" -type f -name "*.gcode" -exec ln -sfn {} "$SYMLINK_DIR" \;
    fi
}

# Function to remove symlinks
remove_symlink() {
    find "$SYMLINK_DIR" -type l -exec test ! -e {} \; -delete
}

# Check if script is being run with a flag
if [ "$1" = "insert" ]; then
    create_symlink
    exit 0
elif [ "$1" = "remove" ]; then
    remove_symlink
    exit 0
fi

# If no valid argument is provided, run the following
# Create or overwrite udev rule for USB automount and symlink handling
echo 'ACTION=="add", SUBSYSTEMS=="usb", SUBSYSTEM=="block", KERNEL=="sd*1", ENV{ID_FS_USAGE}=="filesystem", RUN+="/usr/bin/systemd-mount --no-block --automount=yes --collect --options ro,nofail $devnode /home/mks/printer_data/gcodes/USB", RUN+="/home/mks/OpenNept4une/img-config/usb-storage-automount.sh insert"' | sudo tee $RULE_FILE
echo 'ACTION=="remove", SUBSYSTEMS=="usb", SUBSYSTEM=="block", KERNEL=="sd*1", ENV{ID_FS_USAGE}=="filesystem", RUN+="/home/mks/OpenNept4une/img-config/usb-storage-automount.sh remove"' | sudo tee -a $RULE_FILE

sudo udevadm control --reload-rules && sudo udevadm trigger
echo "Udev rules for USB automount and symlink handling are configured."
