#!/bin/bash

# First User prompt
read -p "This operation will clear any changes to your printer.cfg. Please make sure to back up any files you wish to keep before continuing. Do you wish to continue? (y/n): " response_backup

if [[ $response_backup != "y" && $response_backup != "Y" ]]; then
  echo "Operation aborted. Please back up your files as necessary and try again."
  exit 1
fi

# Second User prompt
read -p "This process currently doesn't support the Neptune 4's touch-screen; all usage going forward will be through the printer's web UI. Do you wish to continue? (y/n): " response_touch_screen

if [[ $response_touch_screen != "y" && $response_touch_screen != "Y" ]]; then
  echo "Operation aborted."
  exit 1
fi

sudo service klipper stop

sudo systemctl start ntp
sudo systemctl enable ntp

sudo systemctl disable elegoo-fix.service
sudo systemctl stop elegoo-fix.service
sudo systemctl disable makerbase-client.service
sudo systemctl stop makerbase-client.service
sudo systemctl disable makerbase-net-mods.service
sudo systemctl stop makerbase-net-mods.service
sudo systemctl stop makerbase-wlan0.service
sudo systemctl disable makerbase-wlan0.service
sudo systemctl stop makerbase-time-monitor
sudo systemctl disable makerbase-time-monitor

sudo service nginx stop

sudo rm /boot/wpa_supplicant/wpa_supplicant-wlan0.conf
sudo rm /etc/wpa_supplicant/wpa_supplicant-wlan0.conf

/klipper/scripts/klipper-uninstall.sh
sudo /home/mks/moonraker/scripts/uninstall-moonraker.sh
sudo /home/mks/crowsnest/tools/uninstall.sh

find /home/mks/ -mindepth 1 ! -name OpenNept4une -exec rm -rf {} +
sudo rm -rf /root/*

# Create the config directory structure if not exists
[ ! -d "/home/mks/printer_data/config/" ] && mkdir -p /home/mks/printer_data/config/

# Clone the KAMP git repository if not exists
[ ! -d "/home/mks/Klipper-Adaptive-Meshing-Purging" ] && cd /home/mks && git clone https://github.com/kyleisah/Klipper-Adaptive-Meshing-Purging.git

# Create a symbolic link if not exists
[ ! -L "/home/mks/printer_data/config/KAMP" ] && ln -s /home/mks/Klipper-Adaptive-Meshing-Purging/Configuration /home/mks/printer_data/config/KAMP

# Clone Kiauh git repository if not exists
[ ! -d "/home/mks/kiauh" ] && cd /home/mks && git clone https://github.com/dw-0/kiauh.git

# Source directory
src_dir="/home/mks/OpenNept4une/OpenNept4une-Script/configuration-files"

# Destination directories
config_dest_dir="/home/mks/printer_data/config"
database_dest_dir="/home/mks/printer_data/database"

# List of configuration files to move
config_files=("KAMP_Settings.cfg" "moonraker.conf" "adxl.cfg" "fluidd.cfg" "printer.cfg")

# Database file to move
database_file="data.mdb"

# Check if source directory exists
if [ ! -d "$src_dir" ]; then
  echo "Error: Source directory does not exist."
  exit 1
fi

# Check if config destination directory exists, create it if it doesn't
if [ ! -d "$config_dest_dir" ]; then
  echo "Config destination directory does not exist. Creating it now."
  mkdir -p "$config_dest_dir"
fi

# Check if database destination directory exists, create it if it doesn't
if [ ! -d "$database_dest_dir" ]; then
  echo "Database destination directory does not exist. Creating it now."
  mkdir -p "$database_dest_dir"
fi

# Move the configuration files
for file in "${config_files[@]}"; do
  if [ -e "$src_dir/$file" ]; then
    mv "$src_dir/$file" "$config_dest_dir"
    echo "Moved: $file"
  else
    echo "Warning: $file does not exist in the source directory."
  fi
done

# Move the database file
if [ -e "$src_dir/$database_file" ]; then
  mv "$src_dir/$database_file" "$database_dest_dir"
  echo "Moved: $database_file"
else
  echo "Warning: $database_file does not exist in the source directory."
fi

echo "Done."

sudo apt-mark hold linux-dtb-edge-rockchip64 linux-image-edge-rockchip64 linux-libc-dev:arm64 linux-u-boot-mkspi-edge armbian-bsp-cli-mkspi armbian-firmware

sudo apt update 
sudo apt remove nginx -y
sudo apt install network-manager -y 
sudo apt dist-upgrade -y
sudo apt clean -y
sudo apt autoclean -y
sudo apt autoremove -y
sudo rm -rf /var/log/*
sudo rm -rf /usr/share/man/*

CRON_ENTRY="*/10 * * * * /bin/sync"
if ! (crontab -l 2>/dev/null | grep "/bin/sync"); then
    (crontab -l 2>/dev/null; echo "$CRON_ENTRY") | crontab -
    echo "Sync command added to the crontab to run every 10 minutes."
else
    echo "The sync command is already in the crontab."
fi

sudo nmtui

sync 

# Run kiauh.sh as the mks user
sudo -u mks /home/mks/kiauh/kiauh.sh
