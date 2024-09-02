#!/bin/bash

# Define the crowsnest directory
CROWSNEST_DIR="${HOME}/crowsnest"

# Check if required commands are available
for cmd in make v4l2-ctl sed systemctl git; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: $cmd command not found. Please install it before running this script."
        exit 1
    fi
done

# Uninstall previous installations if any using make uninstall as the standard user
if [ -d "${CROWSNEST_DIR}" ]; then
    pushd "${CROWSNEST_DIR}" &> /dev/null || exit 1
    echo "Launching crowsnest uninstaller as the standard user..."
    
    if ! make uninstall; then
        echo "Something went wrong during uninstallation! Please try again..."
        exit 1
    fi
    
    echo "Removing crowsnest directory ..."
    rm -rf "${CROWSNEST_DIR}"
    echo "Directory removed!"
    
    popd &> /dev/null
    echo "Crowsnest successfully removed!"
fi

# Remove any remaining crowsnest related files
[ -d "${HOME}/crowsnest/" ] && rm -rf "${HOME}/crowsnest/"
[ -f "${HOME}/printer_data/config/crowsnest.conf" ] && rm -f "${HOME}/printer_data/config/crowsnest.conf"

# Define the file paths
MOONRAKER_CONF="${HOME}/printer_data/config/moonraker.conf"
MOONRAKER_ASVC="${HOME}/printer_data/moonraker.asvc"

# Modify system files with sudo
echo "Modifying system configuration files..."
sed -i '/\[update_manager crowsnest\]/,/^$/d' "$MOONRAKER_CONF"
sed -i '/crowsnest/d' "$MOONRAKER_ASVC"

echo "Sections and entries for 'crowsnest' have been removed from the configuration files."

# Remove camera-streamer related service & files
sudo systemctl disable camera-streamer-generic > /dev/null 2>&1
sudo apt remove camera-streamer-generic -y > /dev/null 2>&1
sudo rm /etc/systemd/system/camera-streamer.service > /dev/null 2>&1

[ -f "${HOME}/camera-streamer-generic*" ] && sudo rm -f "${HOME}/camera-streamer-generic*"

if [ ! -d "${HOME}/mjpg-streamer" ]; then
    # Install dependencies
    echo "Installing dependencies..."
    sudo apt update
    sudo apt autoremove -y 
    sudo apt install -y cmake libjpeg62-turbo-dev gcc g++
    cd {HOME}
    echo "Cloning and building mjpg-streamer..."
    git clone https://github.com/ArduCAM/mjpg-streamer.git || { echo "Failed to clone mjpg-streamer repository"; exit 1; }
    cd mjpg-streamer/mjpg-streamer-experimental || exit 1
    sed -i '/add_subdirectory(plugins\/input_libcamera)/ s/^/#/' ./CMakeLists.txt
    make || { echo "Make failed for mjpg-streamer"; exit 1; }
    sudo make install || { echo "Installation failed for mjpg-streamer"; exit 1; }
    export LD_LIBRARY_PATH=.
    clear
fi

# Initialize the VIDEO_DEVICE variable
VIDEO_DEVICE=""

# List all USB video devices
usb_devices=$(v4l2-ctl --list-devices | grep -A 9999 'usb' | grep -E '/dev/video' | awk '{print $1}')

for device in $usb_devices; do
    FORMATS_OUTPUT=$(v4l2-ctl --device=$device --list-formats-ext)
    if [[ -n "$FORMATS_OUTPUT" ]]; then
        VIDEO_DEVICE="$device"
        break
    fi
done

if [ -z "$VIDEO_DEVICE" ]; then
    echo "No USB video device found. Ensure your camera is connected and recognized by the system."
    exit 1
fi

echo "Detected video device: $VIDEO_DEVICE"

# Initialize arrays to store formats, resolutions, and fps
declare -A formats_map
declare -a formats_order

# Parse the formats, resolutions, and framerates
current_format=""
while IFS= read -r line; do
    if [[ "$line" =~ \[([0-9]+)\]:\ \'(.*)\'\ \((.*)\) ]]; then
        current_format="${BASH_REMATCH[2]}"
        formats_order+=("$current_format")
        formats_map["$current_format"]=""
    elif [[ "$line" =~ Size:\ Discrete\ ([0-9]+x[0-9]+) ]]; then
        resolution="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ Interval:\ Discrete\ ([0-9.]+)s\ \(([0-9.]+)\ fps\) ]]; then
        fps="${BASH_REMATCH[2]}"
        pair="$resolution $fps"
        if [[ ! "${formats_map["$current_format"]}" =~ "$pair" ]]; then
            formats_map["$current_format"]+="$pair\n"
        fi
    fi
done <<< "$FORMATS_OUTPUT"

# Provide the user with a brief explanation of the formats
echo "Please select the video format:"
echo "1) MJPG (Motion-JPEG, compressed):"
echo "   - Pros: Uses less bandwidth, resulting in higher resolutions and frame rates."
echo "   - Cons: Compression can introduce artifacts, particularly in high-motion scenes."
echo ""
echo "2) YUYV (YUYV 4:2:2, uncompressed):"
echo "   - Pros: High-quality video without compression artifacts."
echo "   - Cons: Requires more bandwidth, which can reduce the achievable resolution and frame rate."
echo ""

# Prompt the user to choose a format
video_format=""
read -p "Enter the number of your preferred format (1 for MJPG, 2 for YUYV): " format_choice
# Set the selected format based on user input
if [[ "$format_choice" == "1" ]] && [[ -n "${formats_map["MJPG"]}" ]]; then
    selected_format="MJPG"
elif [[ "$format_choice" == "2" ]] && [[ -n "${formats_map["YUYV"]}" ]]; then
    selected_format="YUYV"
    video_format="-y"
else
    echo "Invalid selection or format not available. Exiting."
    exit 1
fi

# Display available resolutions and framerates for the selected format
echo ""
echo "Available resolutions and framerates for $selected_format:"
IFS=$'\n' read -d '' -r -a res_fps_array <<< "$(echo -e "${formats_map["$selected_format"]}")"
res_index=1
for item in "${res_fps_array[@]}"; do
    echo "$res_index) $item"
    ((res_index++))
done

# Prompt user to select a resolution and framerate by number
read -p "Enter the number of your preferred resolution and framerate: " choice

# Validate user input
if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#res_fps_array[@]}" ]; then
    echo "Invalid selection. Exiting."
    exit 1
fi

selected_res_fps="${res_fps_array[$((choice-1))]}"
selected_resolution=$(echo "$selected_res_fps" | awk '{print $1}')
selected_fps=$(echo "$selected_res_fps" | awk '{print $2}')

# Create or update the MJPG-streamer systemd service file
SERVICE_FILE="/etc/systemd/system/mjpg-streamer.service"

sudo bash -c "cat > $SERVICE_FILE" <<EOL
[Unit]
Description=MJPG Streamer Service
After=network.target

[Service]
ExecStart=/usr/local/bin/mjpg_streamer -i "input_uvc.so -d $VIDEO_DEVICE -r $selected_resolution -f $selected_fps $video_format" -o "output_http.so -w /www/webcam -p 8080"
Restart=always
User=$(whoami)

[Install]
WantedBy=multi-user.target
EOL

# Reload systemd and restart the service
sudo systemctl daemon-reload
sudo systemctl restart mjpg-streamer
sudo systemctl enable mjpg-streamer

echo "Service updated and restarted successfully with resolution $selected_resolution, FPS $selected_fps, and format $selected_format."
echo ""
LOCAL_IP=$(hostname -I | awk '{print $1}')
echo "Configure Fluidd > Settings > Cameras > USB insert the the URL's below"
echo ""
echo "http://$LOCAL_IP:8080/?action=stream"
echo "http://$LOCAL_IP:8080/?action=snapshot"
echo ""
echo "script will auto close in 1 min"
sleep 60
