#!/bin/bash

# Run the first script
chmod +x /home/mks/OpenNept4une/display/display-env-install.sh && /home/mks/OpenNept4une/display/display-env-install.sh

# Define the service file path, script path, and log file path
SERVICE_FILE="/etc/systemd/system/display.service"
SCRIPT_PATH="/home/mks/OpenNept4une/display/display.py"
VENV_PATH="/home/mks/OpenNept4une/display/venv"
LOG_FILE="/var/log/display.log"

# Check if the script exists
if [ ! -f "$SCRIPT_PATH" ]; then
    echo "Error: Script $SCRIPT_PATH not found."
    exit 1
fi

# Create the systemd service file
echo "Creating systemd service file at $SERVICE_FILE..."
cat <<EOF | sudo tee $SERVICE_FILE > /dev/null
[Unit]
Description=OpenNept4une TouchScreen Display Service
After=klipper.service klipper-mcu.service moonraker.service
Wants=klipper.service moonraker.service
Documentation=man:display(8)

[Service]
ExecStartPre=/bin/sleep 5
ExecStart=/home/mks/OpenNept4une/display/venv/bin/python /home/mks/OpenNept4une/display/display.py
WorkingDirectory=/home/mks/OpenNept4une/display
Restart=on-failure
RestartSec=10
User=mks
ProtectSystem=full
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd to read new service file
echo "Reloading systemd..."
sudo systemctl daemon-reload

# Enable and start the service
echo "Enabling and starting the service..."
sudo systemctl enable display.service
sudo systemctl start display.service

echo "Service setup complete."
