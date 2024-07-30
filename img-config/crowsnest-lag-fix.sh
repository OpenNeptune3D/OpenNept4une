#!/bin/bash

# Function to check if the script is run with sudo
check_sudo() {
  if [[ $EUID -ne 0 ]]; then
    echo "This script must be run with sudo. Re-running with sudo..."
    sudo HOME="$HOME" bash "$0" "$@"
    exit $?
  fi
}

# Run the check_sudo function
check_sudo "$@"

# Uninstall previous installations if any
if [ -f "${HOME}/crowsnest/tools/uninstall.sh" ]; then
  ${HOME}/crowsnest/tools/uninstall.sh
fi

# Define the file paths
MOONRAKER_CONF=${HOME}/printer_data/config/moonraker.conf
MOONRAKER_ASVC=${HOME}/printer_data/moonraker.asvc

# Remove the [update_manager crowsnest] section from moonraker.conf
sed -i '/\[update_manager crowsnest\]/,/^$/d' "$MOONRAKER_CONF"

# Remove crowsnest from moonraker.asvc
sed -i '/crowsnest/d' "$MOONRAKER_ASVC"

echo "Sections and entries for 'crowsnest' have been removed from the configuration files."

rm -rf ${HOME}/crowsnest/

rm printer_data/config/crowsnest.conf

# Determine package name
PACKAGE="camera-streamer-$(test -e /etc/default/raspberrypi-kernel && echo raspi || echo generic)_0.2.8.$(. /etc/os-release; echo $VERSION_CODENAME)_$(dpkg --print-architecture).deb"

# Download the package
wget "https://github.com/ayufan/camera-streamer/releases/download/v0.2.8/$PACKAGE"

# Install the package
sudo apt install -y "./$PACKAGE"

sudo systemctl enable camera-streamer
sudo systemctl start camera-streamer

sudo cp /usr/share/camera-streamer/examples/camera-streamer-generic-usb-cam.service /etc/systemd/system/camera-streamer.service
sync

sudo rm ${HOME}/camera-streamer-generic*

# Detect the video device
VIDEO_DEVICE=$(v4l2-ctl --list-devices | grep -A 1 'GENERAL WEBCAM' | tail -n 1 | awk '{print $1}')

if [ -z "$VIDEO_DEVICE" ]; then
  echo "No USB video device found."
  exit 1
fi

echo "Detected video device: $VIDEO_DEVICE"

# Update the systemd service file
SERVICE_FILE="/etc/systemd/system/camera-streamer.service"

if [ -f "$SERVICE_FILE" ]; then
  # Update the camera path
  sudo sed -i "s|-camera-path=/dev/video[0-9]*|--camera-path=$VIDEO_DEVICE|" /etc/systemd/system/camera-streamer.service
  # Update the camera format
  sudo sed -i "s|-camera-format=JPEG|--camera-format=MJPEG|" /etc/systemd/system/camera-streamer.service
  # Update the camera width and height
  sudo sed -i "s|-camera-width=1920 -camera-height=1080|--camera-width=640 --camera-height=480|" /etc/systemd/system/camera-streamer.service
  # Update the camera FPS
  sudo sed -i "s|-camera-fps=30|--camera-fps=30|" /etc/systemd/system/camera-streamer.service
  # Update the http-listen and http-port
  sudo sed -i "s|--http-listen=0.0.0.0|--http-listen=0.0.0.0|" /etc/systemd/system/camera-streamer.service
  sudo sed -i "s|--http-port=8080|--http-port=8080|" /etc/systemd/system/camera-streamer.service
  # Remove lines containing specific settings
  sudo sed -i "/-camera-nbufs=3/d" /etc/systemd/system/camera-streamer.service
  sudo sed -i "/-camera-video.disabled/d" /etc/systemd/system/camera-streamer.service
  # Remove comment lines related to specific settings
  sudo sed -i "/; use two memory buffers to optimise usage/d" /etc/systemd/system/camera-streamer.service
  sudo sed -i "/; disable video streaming (WebRTC, RTSP, H264)/d" /etc/systemd/system/camera-streamer.service
  sudo sed -i "/; on non-supported platforms/d" /etc/systemd/system/camera-streamer.service

  # Reload systemd and restart the service
  sync
  sudo systemctl daemon-reload
  sudo systemctl restart camera-streamer.service
  echo "Service updated and restarted successfully."

else
  echo "Service file not found: $SERVICE_FILE"
  exit 1
fi
