#!/bin/bash

# Run the first script
~/OpenNept4une/display/display-env-install.sh

# Define the service file path, script path, and log file path
SERVICE_FILE="/etc/systemd/system/OpenNept4une.service"
SCRIPT_PATH="$HOME/OpenNept4une/display/display.py"
VENV_PATH="$HOME/OpenNept4une/display/venv"
LOG_FILE="/var/log/display.log"
MOONRAKER_ASVC="$HOME/printer_data/moonraker.asvc"

# Check if the script exists
if [ ! -f "$SCRIPT_PATH" ]; then
    echo "Error: Script $SCRIPT_PATH not found."
    exit 1
fi

# Check if the old service exists and is running
if service --status-all | grep -Fq 'display'; then
    # Stop the service silently
    sudo service display stop >/dev/null 2>&1
    # Disable the service silently
    sudo service display disable >/dev/null 2>&1
else
    echo "Continuing..."
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
ExecStartPre=/bin/sleep 10
ExecStart=/home/mks/OpenNept4une/display/venv/bin/python /home/mks/OpenNept4une/display/display.py
WorkingDirectory=/home/mks/OpenNept4une/display
Restart=on-failure
CPUQuota=50%
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
sudo systemctl enable OpenNept4une.service
sudo systemctl start OpenNept4une.service

echo "Allowing Moonraker to control display service"
grep -qxF 'OpenNept4une' $MOONRAKER_ASVC || echo 'OpenNept4une' >> $MOONRAKER_ASVC

# Define the lines to be inserted or updated
new_lines="[update_manager OpenNept4une]
type: git_repo
primary_branch: main
path: ~/OpenNept4une
origin: https://github.com/halfmanbear/OpenNept4une.git"

# Define the path to the moonraker.conf file
config_file="$HOME/printer_data/config/moonraker.conf"

# Check if the lines exist in the config file
if grep -qF "[update_manager OpenNept4une]" "$config_file"; then
    # Lines exist, update them
    sed -i "/[update_manager OpenNept4une]/,/^$/c$new_lines" "$config_file"
else
    # Lines do not exist, append them to the end of the file
    echo -e "\n$new_lines" >> "$config_file"
fi

echo "Service setup complete."

sudo service moonraker restart 
