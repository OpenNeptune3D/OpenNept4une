#!/bin/bash

# Remove old mount directory if it exists 
sudo rm -f /etc/udev/rules.d/99-usb_automount.rules

# Define the path for the udev rule file
udev_rule_path="/etc/udev/rules.d/99-usb_automount.rules"

# Define the mount point
mount_point="/home/mks/printer_data/gcodes/USB"

# Obtain UID and GID for the mks user
uid=$(id -u mks)
gid=$(id -g mks)

# Udev rule to add
udev_rule_add="ACTION==\"add\", SUBSYSTEMS==\"usb\", SUBSYSTEM==\"block\", KERNEL==\"sd*1\", ENV{ID_FS_USAGE}==\"filesystem\", RUN{program}+=\"/usr/bin/systemd-mount --no-block --automount=yes --collect --options uid=$uid,gid=$gid,sync,nofail \$devnode $mount_point\""

# Udev rule to remove
udev_rule_remove="ACTION==\"remove\", SUBSYSTEMS==\"usb\", SUBSYSTEM==\"block\", KERNEL==\"sd*1\", RUN+=\"/bin/sh -c '/bin/umount $mount_point'\""

# Write the rules to the udev rule file
{
    echo "$udev_rule_add"
    echo "$udev_rule_remove"
} | sudo tee "$udev_rule_path"

# Create the mount point directory if it doesn't exist
if [ ! -d "$mount_point" ]; then
    sudo mkdir -p "$mount_point"
fi

# Change the ownership of the mount point to user 'mks'
sudo chown mks:mks "$mount_point"

# Reload udev rules
sudo udevadm control --reload-rules && sudo udevadm trigger

echo "Udev rule for USB automount with sync option is configured."
