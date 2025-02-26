#!/bin/bash

# Log all output to a logfile
LOGFILE="${HOME}/webcam_setup.log"
exec > >(tee -a "$LOGFILE") 2>&1

###############################################################################
# 1. Prompt user for number of webcams
###############################################################################
echo ""
echo "How many webcams do you wish to configure? (1 or 2)"
read -r -p "Enter 1 or 2: " num_webcams

if [[ "$num_webcams" != "1" && "$num_webcams" != "2" ]]; then
    echo ""
    echo "Invalid input. Please enter either 1 or 2. Exiting."
    exit 1
fi

###############################################################################
# 2. Check for required commands
###############################################################################
for cmd in make v4l2-ctl sed systemctl git; do
    if ! command -v "$cmd" &> /dev/null; then
        echo ""
        echo "Error: $cmd command not found. Please install it before running this script."
        exit 1
    fi
done

###############################################################################
# 3. Remove old Crowsnest if present
###############################################################################
CROWSNEST_DIR="${HOME}/crowsnest"

if [ -d "${CROWSNEST_DIR}" ]; then
    pushd "${CROWSNEST_DIR}" &> /dev/null || exit 1
    echo ""
    echo "Launching crowsnest uninstaller as the standard user..."
    
    if ! make uninstall; then
        echo ""
        echo "Something went wrong during uninstallation! Please try again..."
        exit 1
    fi
    
    echo ""
    echo "Removing crowsnest directory ..."
    rm -rf "${CROWSNEST_DIR}"
    echo ""
    echo "Directory removed!"
    
    popd &> /dev/null || exit
    echo ""
    echo "Crowsnest successfully removed!"
fi

rm -rf "${HOME}/crowsnest/" > /dev/null 2>&1
rm -f "${HOME}/printer_data/config/crowsnest.conf" > /dev/null 2>&1

###############################################################################
# 4. Remove crowsnest references from Moonraker config
###############################################################################
MOONRAKER_CONF="${HOME}/printer_data/config/moonraker.conf"
MOONRAKER_ASVC="${HOME}/printer_data/moonraker.asvc"

echo ""
echo "Modifying system configuration files..."
sed -i '/\[update_manager crowsnest\]/,/^$/d' "$MOONRAKER_CONF"
sed -i '/crowsnest/d' "$MOONRAKER_ASVC"
echo ""
echo "Sections and entries for 'crowsnest' have been removed from the configuration files."

###############################################################################
# 5. Remove camera-streamer related services and files
###############################################################################
sudo systemctl disable camera-streamer-generic > /dev/null 2>&1
sudo apt remove camera-streamer-generic -y > /dev/null 2>&1
sudo rm /etc/systemd/system/camera-streamer.service > /dev/null 2>&1
sudo rm -f "${HOME}/camera-streamer-generic*"

###############################################################################
# 6. Remove old mjpg-streamer services
###############################################################################
echo ""
echo "Removing leftover MJPG-streamer services from any previous runs..."
sudo systemctl stop mjpg-streamer-webcam*.service > /dev/null 2>&1
sudo systemctl disable mjpg-streamer-webcam*.service > /dev/null 2>&1
sudo rm -f /etc/systemd/system/mjpg-streamer-webcam*.service
sudo systemctl daemon-reload

###############################################################################
# 7. Install mjpg-streamer if not already present
###############################################################################
if [ ! -d "${HOME}/mjpg-streamer" ]; then
    echo ""
    echo "Installing dependencies..."
    sudo apt update
    sudo apt autoremove -y
    sudo apt install -y cmake libjpeg62-turbo-dev gcc g++
    
    cd "$HOME" || exit
    echo ""
    echo "Cloning and building mjpg-streamer..."
    git clone https://github.com/ArduCAM/mjpg-streamer.git || {
        echo ""
        echo "Failed to clone mjpg-streamer repository"
        exit 1
    }
    
    cd mjpg-streamer/mjpg-streamer-experimental || exit 1
    # Comment out input_libcamera plugin if present
    sed -i '/add_subdirectory(plugins\/input_libcamera)/ s/^/#/' ./CMakeLists.txt
    
    make || {
        echo ""
        echo "Make failed for mjpg-streamer"
        exit 1
    }
    sudo make install || {
        echo ""
        echo "Installation failed for mjpg-streamer"
        exit 1
    }
    export LD_LIBRARY_PATH=.
    clear
fi

###############################################################################
# 8. Detect USB webcams
###############################################################################
valid_video_devices=()

# This looks for any line containing 'usb', then the next lines for /dev/video*
usb_devices=$(v4l2-ctl --list-devices | grep -A 9999 'usb' | grep -E '/dev/video' | awk '{print $1}')

for device in $usb_devices; do
    FORMATS_OUTPUT=$(v4l2-ctl --device="$device" --list-formats-ext)
    if [[ -n "$FORMATS_OUTPUT" ]]; then
        # Check if the output contains 'MJPG' or 'YUYV'
        if echo "$FORMATS_OUTPUT" | grep -q -E 'MJPG|YUYV'; then
            valid_video_devices+=("$device")
            echo ""
            echo "Valid video device found: $device"
        else
            echo ""
            echo "Device $device does not support MJPG or YUYV. Ignoring."
        fi
    fi
done

# Ensure we have enough devices for user's selection
if [[ ${#valid_video_devices[@]} -lt "$num_webcams" ]]; then
    echo ""
    echo "You have selected to configure $num_webcams webcam(s), but only ${#valid_video_devices[@]} valid webcam(s) were found."
    exit 1
fi

###############################################################################
# 9. Configuration loop for each webcam
###############################################################################
LOCAL_IP=$(hostname -I | awk '{print $1}')

for (( i=1; i<=num_webcams; i++ )); do
    echo ""
    echo "Configuring webcam $i of $num_webcams"
    
    # If more than one valid device left, prompt user to choose
    if [[ ${#valid_video_devices[@]} -gt 1 ]]; then
        echo ""
        echo "Multiple valid video devices detected:"
        for j in "${!valid_video_devices[@]}"; do
            echo "$((j+1))) ${valid_video_devices[$j]}"
        done
        read -r -p "Enter the number of the device you want to use for webcam $i: " device_choice
        
        if ! [[ "$device_choice" =~ ^[0-9]+$ && \
                "$device_choice" -ge 1 && \
                "$device_choice" -le "${#valid_video_devices[@]}" ]]; then
            echo ""
            echo "Invalid selection. Exiting."
            exit 1
        fi
        
        VIDEO_DEVICE="${valid_video_devices[$((device_choice-1))]}"
    else
        VIDEO_DEVICE="${valid_video_devices[0]}"
    fi

    echo ""
    echo "Selected video device: $VIDEO_DEVICE for webcam $i"

    # Remove the chosen device from the array to avoid duplicates in next iteration
    unset "valid_video_devices[$((device_choice-1))]"
    # Rebuild the array to remove the empty entry
    valid_video_devices=("${valid_video_devices[@]}")

    # Get all supported formats/resolutions/fps
    FORMATS_OUTPUT=$(v4l2-ctl --device="$VIDEO_DEVICE" --list-formats-ext)

    # Prepare to parse them
    declare -A formats_map
    declare -a formats_order

    current_format=""
    while IFS= read -r line; do
        # Example lines we might see:
        # [0]: 'MJPG' (Motion-JPEG, compressed)
        #   Size: Discrete 640x480
        #     Interval: Discrete 0.033s (30.000 fps)
        
        if [[ "$line" =~ \[([0-9]+)\]:\ \'(.*)\'\ \((.*)\) ]]; then
            current_format="${BASH_REMATCH[2]}"
            formats_order+=("$current_format")
            formats_map["$current_format"]=""
        
        elif [[ "$line" =~ Size:\ Discrete\ ([0-9]+x[0-9]+) ]]; then
            resolution="${BASH_REMATCH[1]}"
        
        elif [[ "$line" =~ Interval:\ Discrete\ ([0-9.]+)s\ \(([0-9.]+)\ fps\) ]]; then
            fps="${BASH_REMATCH[2]}"
            pair="$resolution $fps"
            
            # Avoid duplicates
            if [[ ! ${formats_map[$current_format]} =~ $pair ]]; then
                formats_map["$current_format"]+="$pair\n"
            fi
        fi
    done <<< "$FORMATS_OUTPUT"

    if [[ ${#formats_order[@]} -eq 0 ]]; then
        echo ""
        echo "No valid formats found for the selected video device. Exiting."
        exit 1
    fi

    # Prompt user for MJPG or YUYV
    echo ""
    echo "Please select the video format for webcam $i:"
    echo "1) MJPG (Motion-JPEG, compressed)"
    echo "2) YUYV (YUYV 4:2:2, uncompressed)"
    
    video_format=""
    read -r -p "Enter the number of your preferred format (1 for MJPG, 2 for YUYV): " format_choice
    if [[ "$format_choice" == "1" ]] && [[ -n "${formats_map["MJPG"]}" ]]; then
        selected_format="MJPG"
    elif [[ "$format_choice" == "2" ]] && [[ -n "${formats_map["YUYV"]}" ]]; then
        selected_format="YUYV"
        # MJPG-streamer uses -y for YUYV input in input_uvc.so
        video_format="-y"
    else
        echo ""
        echo "Invalid selection or format not available. Exiting."
        exit 1
    fi

    # Display the possible resolution/FPS combos for that format
    echo ""
    echo "Available resolutions and framerates for $selected_format on webcam $i:"
    IFS=$'\n' read -r -d '' -a res_fps_array <<< "$(echo -e "${formats_map["$selected_format"]}")"
    
    res_index=1
    for item in "${res_fps_array[@]}"; do
        echo "$res_index) $item"
        ((res_index++))
    done

    read -r -p "Enter the number of your preferred resolution and framerate: " choice
    if ! [[ "$choice" =~ ^[0-9]+$ && \
            "$choice" -ge 1 && \
            "$choice" -le "${#res_fps_array[@]}" ]]; then
        echo ""
        echo "Invalid selection. Exiting."
        exit 1
    fi

    selected_res_fps="${res_fps_array[$((choice-1))]}"
    selected_resolution=$(echo "$selected_res_fps" | awk '{print $1}')
    selected_fps=$(echo "$selected_res_fps" | awk '{print $2}')

    # Remove a legacy generic service file, if it exists
    sudo rm /etc/systemd/system/mjpg-streamer.service > /dev/null 2>&1

    # Create a unique systemd service for this webcam
    SERVICE_FILE="/etc/systemd/system/mjpg-streamer-webcam$i.service"

    # Assign a unique port (8080 for first, 8081 for second, etc.)
    STREAM_PORT=$((8080 + i - 1))

    sudo bash -c "cat > $SERVICE_FILE" <<EOL
[Unit]
Description=MJPG Streamer Service for Webcam $i
After=network.target

[Service]
ExecStart=/usr/local/bin/mjpg_streamer -i "input_uvc.so -d $VIDEO_DEVICE -r $selected_resolution -f $selected_fps $video_format" -o "output_http.so -w /www/webcam -p $STREAM_PORT"
Restart=always
User=$(whoami)

[Install]
WantedBy=multi-user.target
EOL

    # Reload systemd and start the service
    sudo systemctl daemon-reload || {
        echo "Failed to reload daemon. Exiting."
        exit 1
    }
    sudo systemctl restart mjpg-streamer-webcam$i || {
        echo "Failed to restart service for webcam $i. Exiting."
        exit 1
    }
    sudo systemctl enable mjpg-streamer-webcam$i || {
        echo "Failed to enable service for webcam $i. Exiting."
        exit 1
    }

    echo ""
    echo "Service for webcam $i updated and restarted successfully."
    echo "Resolution: $selected_resolution"
    echo "Framerate:  $selected_fps"
    echo "Format:     $selected_format"
    echo "Stream URL: http://$LOCAL_IP:$STREAM_PORT/?action=stream"
done

echo ""
echo "Configuration completed."
