#!/bin/bash
set -e

# Log all output to a logfile
LOGFILE="${HOME}/webcam_setup.log"
exec > >(tee -a "$LOGFILE") 2>&1

# Ask the user how many webcams they want to configure
echo ""
echo "How many webcams do you wish to configure? (1 or 2)"
while true; do
    read -r -p "Enter 1 or 2: " num_webcams
    if [[ "$num_webcams" == "1" || "$num_webcams" == "2" ]]; then
        break
    else
        echo "Invalid input. Please enter either 1 or 2."
    fi
done

# Define the crowsnest directory
CROWSNEST_DIR="${HOME}/crowsnest"

# Check if required commands are available
for cmd in make v4l2-ctl sed systemctl git; do
    if ! command -v "$cmd" &> /dev/null; then
        echo ""
        echo "Error: $cmd command not found. Please install it before running this script."
        exit 1
    fi
done

# Uninstall previous installations if any using make uninstall as the standard user
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

# Remove any remaining crowsnest related files
rm -rf "${HOME}/crowsnest/" > /dev/null 2>&1
rm -f "${HOME}/printer_data/config/crowsnest.conf" > /dev/null 2>&1

# Define the file paths
MOONRAKER_CONF="${HOME}/printer_data/config/moonraker.conf"
MOONRAKER_ASVC="${HOME}/printer_data/moonraker.asvc"

# Modify system files with sudo
echo ""
echo "Modifying system configuration files..."
sed -i '/update_manager crowsnest/,/^$/d' "$MOONRAKER_CONF"
sed -i '/crowsnest/d' "$MOONRAKER_ASVC"

echo ""
echo "Sections and entries for 'crowsnest' have been removed from the configuration files."

# Remove camera-streamer related service & files
sudo systemctl disable camera-streamer-generic > /dev/null 2>&1
sudo apt remove camera-streamer-generic -y > /dev/null 2>&1
sudo rm /etc/systemd/system/camera-streamer.service > /dev/null 2>&1
sudo rm -f "${HOME}/camera-streamer-generic*"

# Install mjpg-streamer if not already present
if [ ! -d "${HOME}/mjpg-streamer" ]; then
    echo ""
    echo "Installing dependencies..."
    sudo apt update
    sudo apt autoremove -y 
    sudo apt install -y cmake libjpeg62-turbo-dev gcc g++ build-essential v4l-utils
    cd "$HOME" || exit
    echo ""
    echo "Cloning and building mjpg-streamer..."
    git clone https://github.com/ArduCAM/mjpg-streamer.git || { echo ""; echo "Failed to clone mjpg-streamer repository"; exit 1; }
    cd mjpg-streamer/mjpg-streamer-experimental || exit 1
    sed -i '/add_subdirectory(plugins\/input_libcamera)/ s/^/#/' ./CMakeLists.txt
    make || { echo ""; echo "Make failed for mjpg-streamer"; exit 1; }
    sudo make install || { echo ""; echo "Installation failed for mjpg-streamer"; exit 1; }
    export LD_LIBRARY_PATH=.
    clear
fi

# Initialize an array to store all valid video devices
valid_video_devices=()

# List all USB video devices
usb_devices=$(v4l2-ctl --list-devices | grep -A 9999 'usb' | grep -E '/dev/video' | awk '{print $1}')

for device in $usb_devices; do
    FORMATS_OUTPUT=$(v4l2-ctl --device="$device" --list-formats-ext 2>/dev/null)
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

# Check if there are enough valid devices to match the user's input
if [[ ${#valid_video_devices[@]} -lt "$num_webcams" ]]; then
    echo ""
    echo "You have selected to configure $num_webcams webcam(s), but only ${#valid_video_devices[@]} valid webcam(s) were found."
    exit 1
fi

# Set the local IP address
LOCAL_IP=$(hostname -I | awk '{print $1}')

# Loop through the configuration for each webcam
for (( i=1; i<=num_webcams; i++ )); do
    echo ""
    echo "Configuring webcam $i of $num_webcams"
    
    # Allow the user to select a webcam
    if [[ ${#valid_video_devices[@]} -gt 1 ]]; then
        echo ""
        echo "Multiple valid video devices detected:"
        for j in "${!valid_video_devices[@]}"; do
            echo "$((j+1))) ${valid_video_devices[$j]}"
        done
        while true; do
            read -r -p "Enter the number of the device you want to use for webcam $i: " device_choice
            if [[ "$device_choice" =~ ^[0-9]+$ && "$device_choice" -ge 1 && "$device_choice" -le "${#valid_video_devices[@]}" ]]; then
                VIDEO_DEVICE="${valid_video_devices[$((device_choice-1))]}"
                # Remove the selected device from the list
                unset 'valid_video_devices[$((device_choice-1))]'
                valid_video_devices=("${valid_video_devices[@]}")
                break
            else
                echo "Invalid selection. Please try again."
            fi
        done
    else
        VIDEO_DEVICE="${valid_video_devices[0]}"
    fi

    echo ""
    echo "Selected video device: $VIDEO_DEVICE for webcam $i"

    # The rest of the configuration for formats and resolutions follows here
    FORMATS_OUTPUT=$(v4l2-ctl --device="$VIDEO_DEVICE" --list-formats-ext 2>/dev/null)

    # Declare arrays to store formats, resolutions, and fps
    declare -A formats_map
    declare -a formats_order

    current_format=""
    while IFS= read -r line; do
        if [[ "$line" =~ ([0-9]+):\ \'(.*)\'\ (.*) ]]; then
            current_format="${BASH_REMATCH[2]}"
            formats_order+=("$current_format")
            formats_map["$current_format"]=""
        elif [[ "$line" =~ Size:\ Discrete\ ([0-9]+x[0-9]+) ]]; then
            resolution="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ Interval:\ Discrete\ ([0-9.]+)s\ ([0-9.]+)\ fps ]]; then
            fps="${BASH_REMATCH[2]}"
            pair="$resolution $fps"
            if [[ ! ${formats_map[$current_format]} =~ $pair ]]; then
                formats_map["$current_format"]+="$pair"$'\n'
            fi
        fi
    done <<< "$FORMATS_OUTPUT"

    if [[ ${#formats_order[@]} -eq 0 ]]; then
        echo ""
        echo "No valid formats found for the selected video device. Exiting."
        exit 1
    fi

    # Allow the user to select the video format
    while true; do
        echo ""
        echo "Please select the video format for webcam $i:"
        available_formats=()
        index=1
        for fmt in "${formats_order[@]}"; do
            if [[ "$fmt" == "MJPG" || "$fmt" == "YUYV" ]]; then
                available_formats+=("$fmt")
                if [[ "$fmt" == "MJPG" ]]; then
                    echo "$index) MJPG (Motion-JPEG, compressed)"
                elif [[ "$fmt" == "YUYV" ]]; then
                    echo "$index) YUYV (YUYV 4:2:2, uncompressed)"
                fi
                ((index++))
            fi
        done

        if [[ ${#available_formats[@]} -eq 0 ]]; then
            echo "No suitable formats (MJPG or YUYV) available on this device."
            exit 1
        fi

        read -r -p "Enter the number of your preferred format: " format_choice
        if [[ "$format_choice" =~ ^[0-9]+$ && "$format_choice" -ge 1 && "$format_choice" -le "${#available_formats[@]}" ]]; then
            selected_format="${available_formats[$((format_choice-1))]}"
            if [[ "$selected_format" == "YUYV" ]]; then
                video_format="-y"
            else
                video_format=""
            fi
            break
        else
            echo "Invalid selection. Please try again."
        fi
    done

    echo ""
    echo "Available resolutions and framerates for $selected_format on webcam $i:"
    mapfile -t res_fps_array <<< "${formats_map["$selected_format"]}"
    res_index=1
    for item in "${res_fps_array[@]}"; do
        echo "$res_index) $item"
        ((res_index++))
    done

    while true; do
        read -r -p "Enter the number of your preferred resolution and framerate: " choice
        if [[ "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -le "${#res_fps_array[@]}" ]]; then
            selected_res_fps="${res_fps_array[$((choice-1))]}"
            selected_resolution=$(echo "$selected_res_fps" | awk '{print $1}')
            selected_fps=$(echo "$selected_res_fps" | awk '{print $2}')
            break
        else
            echo "Invalid selection. Please try again."
        fi
    done

    # Remove legacy service file
    sudo systemctl stop mjpg-streamer > /dev/null 2>&1
    sudo systemctl disable mjpg-streamer > /dev/null 2>&1
    sudo rm -f /etc/systemd/system/mjpg-streamer.service

    # Create a unique systemd service file for each webcam
    SERVICE_FILE="/etc/systemd/system/mjpg-streamer-webcam$i.service"

    # Assign a unique port to each webcam (8080 for the first, 8081 for the second)
    STREAM_PORT=$((8080 + i - 1))

    sudo bash -c "cat > $SERVICE_FILE" <<EOL
[Unit]
Description=MJPG Streamer Service for Webcam $i
After=network.target

[Service]
ExecStart=/usr/local/bin/mjpg_streamer -i "input_uvc.so -d \$VIDEO_DEVICE -r \$selected_resolution -f \$selected_fps \$video_format" -o "output_http.so -w /usr/local/www -p \$STREAM_PORT"
Restart=always
User=$(whoami)

[Install]
WantedBy=multi-user.target
EOL

    # Reload, restart, and enable the service
    sudo systemctl daemon-reload || { echo "Failed to reload daemon. Exiting."; exit 1; }
    sudo systemctl restart mjpg-streamer-webcam$i || { echo "Failed to restart service for webcam $i. Exiting."; exit 1; }
    sudo systemctl enable mjpg-streamer-webcam$i || { echo "Failed to enable service for webcam $i. Exiting."; exit 1; }

    echo ""
    echo "Service for webcam $i updated and restarted successfully with resolution $selected_resolution, FPS $selected_fps, and format $selected_format."
    echo "Access webcam $i at: http://$LOCAL_IP:$STREAM_PORT/?action=stream"
done

echo ""
echo "Configuration completed."
