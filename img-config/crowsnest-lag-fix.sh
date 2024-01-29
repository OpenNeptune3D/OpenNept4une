#!/bin/bash

# Create symbolic link for ustreamer
ln -sfn /usr/bin/ustreamer ~/crowsnest/bin/ustreamer/ustreamer

# Create symbolic link for ustreamer-dump
ln -sfn /usr/bin/ustreamer-dump ~/crowsnest/bin/ustreamer/ustreamer-dump

# Path to the log and configuration files
LOG_FILE="${HOME}/printer_data/logs/crowsnest.log"
CONF_FILE="${HOME}/printer_data/config/crowsnest.conf"

# Search for the video device in the log file
# The grep command looks for lines that map the camera to a video device, capturing the last part that starts with '/dev/video'
DEVICE_PATH=$(grep -o ' -> /dev/video[0-9]\+' "$LOG_FILE" | tail -1) # Using 'tail -1' to get the last match, if multiple

# Check if a device path was found
if [ -z "$DEVICE_PATH" ]; then
    echo "No video device path found in the log file."
    exit 1
fi

echo "$DEVICE_PATH"
sleep 3
# Update the configuration file with the detected video device path
# This sed command looks for the line starting with 'device:' and replaces it with the new device path
sed -i "s|device: /dev/video[0-9]\+|device: $DEVICE_PATH|" "$CONF_FILE"
echo
echo "Updated configuration file with video device path: $DEVICE_PATH"
