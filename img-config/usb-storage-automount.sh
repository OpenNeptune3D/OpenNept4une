#!/bin/bash

# Remove old udev rule file if it exists
sudo rm -f /etc/udev/rules.d/99-usb_automount.rules

# Define the path for the udev rule file
udev_rule_path="/etc/udev/rules.d/99-usb_automount.rules"

# Define the mount point
mount_point="/home/mks/printer_data/gcodes/USB"

# Obtain UID and GID for the 'mks' user
uid=$(id -u mks)
gid=$(id -g mks)

# Create the mount point directory if it doesn't exist
if [ ! -d "$mount_point" ]; then
    sudo mkdir -p "$mount_point"
fi

# Change the ownership of the mount point to user 'mks'
sudo chown mks:mks "$mount_point"

# Create the USB automount script with enhancements
sudo tee /usr/local/bin/usb_automount.sh > /dev/null <<'EOL'
#!/bin/bash

# This script mounts or unmounts USB devices
# Usage: usb_automount.sh add|remove device_node mount_point uid gid

action="$1"
device_node="$2"
mount_point="$3"
uid="$4"
gid="$5"

log_file="/var/log/usb_automount.log"

if [ "$action" == "add" ]; then
    # Delay before attempting to mount
    sleep 5

    # Retry mechanism
    max_retries=3
    retry_delay=2
    attempt=1

    while [ $attempt -le $max_retries ]; do
        echo "$(date): Attempt $attempt to mount $device_node" >> "$log_file"

        # Attempt to mount
        /usr/bin/systemd-mount --no-block --automount=yes --collect \
            --options uid=$uid,gid=$gid,flush,nofail "$device_node" "$mount_point" >> "$log_file" 2>&1

        # Check if mount was successful
        if mountpoint -q "$mount_point"; then
            echo "$(date): Successfully mounted $device_node at $mount_point" >> "$log_file"
            exit 0
        else
            echo "$(date): Failed to mount $device_node. Retrying in $retry_delay seconds..." >> "$log_file"
            sleep $retry_delay
            attempt=$((attempt + 1))
        fi
    done

    echo "$(date): Failed to mount $device_node after $max_retries attempts." >> "$log_file"

elif [ "$action" == "remove" ]; then
    # Check if the mount point is mounted
    if mountpoint -q "$mount_point"; then
        # Attempt to unmount
        /usr/bin/systemd-umount "$mount_point" >> "$log_file" 2>&1
        echo "$(date): Unmounted $mount_point" >> "$log_file"
    else
        echo "$(date): $mount_point is not mounted. Skipping unmount." >> "$log_file"
    fi
fi
EOL

# Make the script executable
sudo chmod +x /usr/local/bin/usb_automount.sh

# Udev rule to add
udev_rule_add="ACTION==\"add\", SUBSYSTEM==\"block\", SUBSYSTEMS==\"usb\", ENV{DEVTYPE}==\"partition\", \
ENV{ID_FS_USAGE}==\"filesystem\", RUN+=\"/usr/local/bin/usb_automount.sh add %E{DEVNAME} $mount_point $uid $gid\""

# Udev rule to remove
udev_rule_remove="ACTION==\"remove\", SUBSYSTEM==\"block\", SUBSYSTEMS==\"usb\", ENV{DEVTYPE}==\"partition\", \
RUN+=\"/usr/local/bin/usb_automount.sh remove %E{DEVNAME} $mount_point $uid $gid\""

# Write the rules to the udev rule file
echo "$udev_rule_add" | sudo tee "$udev_rule_path" > /dev/null
echo "$udev_rule_remove" | sudo tee -a "$udev_rule_path" > /dev/null

# Reload udev rules
sudo udevadm control --reload-rules && sudo udevadm trigger

echo "Udev rule for USB automount is configured with enhancements for exFAT/FAT32 and safe removal."
