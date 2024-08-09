#!/bin/bash

# Define the crowsnest directory
CROWSNEST_DIR="${HOME}/crowsnest"

# Uninstall previous installations if any using make uninstall as the standard user
if [ -d "${CROWSNEST_DIR}" ]; then
  pushd "${CROWSNEST_DIR}" &> /dev/null || exit 1
  echo "Launching crowsnest uninstaller as the standard user..."

  # Run make uninstall as the current user (no sudo)
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

# Define the file paths
MOONRAKER_CONF="${HOME}/printer_data/config/moonraker.conf"
MOONRAKER_ASVC="${HOME}/printer_data/moonraker.asvc"

# Modify system files with sudo
echo "Modifying system configuration files..."

# Remove the [update_manager crowsnest] section from moonraker.conf
sed -i '/\[update_manager crowsnest\]/,/^$/d' "$MOONRAKER_CONF"

# Remove crowsnest from moonraker.asvc
sed -i '/crowsnest/d' "$MOONRAKER_ASVC"

echo "Sections and entries for 'crowsnest' have been removed from the configuration files."

# Remove crowsnest related files
rm -rf "${HOME}/crowsnest/"

if [ -f "${HOME}/printer_data/config/crowsnest.conf" ]; then
  rm -f "${HOME}/printer_data/config/crowsnest.conf"
fi

# Determine package name
PACKAGE="camera-streamer-$(test -e /etc/default/raspberrypi-kernel && echo raspi || echo generic)_0.2.8.$(. /etc/os-release; echo $VERSION_CODENAME)_$(dpkg --print-architecture).deb"

# Download the package
echo "Downloading the camera-streamer package..."
wget "https://github.com/ayufan/camera-streamer/releases/download/v0.2.8/$PACKAGE" -P ${HOME} > /dev/null 2>&1

# Install the package with sudo
echo "Installing the camera-streamer package..."
sudo apt install -y "${HOME}/$PACKAGE"

sudo systemctl enable camera-streamer
sudo systemctl start camera-streamer

sudo cp /usr/share/camera-streamer/examples/camera-streamer-generic-usb-cam.service /etc/systemd/system/camera-streamer.service

rm "${HOME}/camera-streamer-generic*"

# Initialize the VIDEO_DEVICE variable
VIDEO_DEVICE=""

# List all USB video devices
usb_devices=$(v4l2-ctl --list-devices | grep -A 9999 'usb' | grep -E '/dev/video' | awk '{print $1}')

# Check each USB video device for MJPEG support
for device in $usb_devices; do
    if v4l2-ctl --device=$device --list-formats | grep -q 'MJPG'; then
        VIDEO_DEVICE="$device"
        break
    fi
done

if [ -z "$VIDEO_DEVICE" ]; then
  echo "No USB video device found that supports MJPG."
  exit 1
fi

echo "Detected video device: $VIDEO_DEVICE"

# Update the systemd service file with sudo
SERVICE_FILE="/etc/systemd/system/camera-streamer.service"

if [ -f "$SERVICE_FILE" ]; then
  # Update the camera path
  sudo sed -i "s|-camera-path=/dev/video[0-9]*|-camera-path=$VIDEO_DEVICE|" "$SERVICE_FILE"
  # Update the camera format
  sudo sed -i "s|-camera-format=JPEG|-camera-format=MJPEG|" "$SERVICE_FILE"
  # Update the camera width and height
  sudo sed -i "s|-camera-width=1920 -camera-height=1080|-camera-width=640 -camera-height=480|" "$SERVICE_FILE"
  # Update the camera FPS
  sudo sed -i "s|-camera-fps=30|-camera-fps=30|" "$SERVICE_FILE"
  # Update the http-listen and http-port
  sudo sed -i "s|--http-listen=0.0.0.0|--http-listen=0.0.0.0|" "$SERVICE_FILE"
  sudo sed -i "s|--http-port=8080|--http-port=8080|" "$SERVICE_FILE"
  # Remove lines containing specific settings
  sudo sed -i "/-camera-nbufs=3/d" "$SERVICE_FILE"
  sudo sed -i "/-camera-video.disabled/d" "$SERVICE_FILE"
  # Remove comment lines related to specific settings
  sudo sed -i "/; use two memory buffers to optimise usage/d" "$SERVICE_FILE"
  sudo sed -i "/; disable video streaming (WebRTC, RTSP, H264)/d" "$SERVICE_FILE"
  sudo sed -i "/; on non-supported platforms/d" "$SERVICE_FILE"

  # Reload systemd and restart the service
  sudo systemctl daemon-reload
  sudo systemctl restart camera-streamer.service
  echo "Service updated and restarted successfully."

else
  echo "Service file not found: $SERVICE_FILE"
  exit 1
fi
