#!/bin/bash

# Ensure the script is run with sudo
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this script with sudo."
    exit 1
fi

# Create the config directory structure if not exists
[ ! -d "$HOME/printer_data/config/" ] && mkdir -p "$HOME/printer_data/config/"

# Change ownership of the printer_data directory to the user who runs the script
chown -R "$SUDO_USER:$SUDO_USER" "$HOME/printer_data"

# Clone the KAMP git repository if not exists
if [ ! -d "$HOME/Klipper-Adaptive-Meshing-Purging" ]; then
    git clone https://github.com/kyleisah/Klipper-Adaptive-Meshing-Purging.git "$HOME/Klipper-Adaptive-Meshing-Purging"
fi

# Create a symbolic link if not exists
[ ! -L "$HOME/printer_data/config/KAMP" ] && ln -s "$HOME/Klipper-Adaptive-Meshing-Purging/Configuration" "$HOME/printer_data/config/KAMP"

# Clone Kiauh git repository if not exists
if [ ! -d "$HOME/kiauh" ]; then
    git clone https://github.com/dw-0/kiauh.git "$HOME/kiauh"
fi

# Add extraargs to armbianEnv.txt if not exists
FILE_PATH="/boot/armbianEnv.txt"
LINE_TO_ADD="extraargs=net.ifnames=0"
if ! grep -q "$LINE_TO_ADD" "$FILE_PATH"; then
    echo "$LINE_TO_ADD" | tee -a "$FILE_PATH" > /dev/null
    echo "Added '$LINE_TO_ADD' to $FILE_PATH."
else
    echo "The line '$LINE_TO_ADD' already exists in $FILE_PATH."
fi

# Hardcoded list of GitHub raw links paired with filenames
declare -A LINKS_AND_NAMES=(
    ["https://raw.githubusercontent.com/OpenNeptune3D/OpenNept4une/main/img-config/printer-data/printer.cfg"]="printer.cfg"
    ["https://raw.githubusercontent.com/OpenNeptune3D/OpenNept4une/main/img-config/printer-data/moonraker.conf"]="moonraker.conf"
    ["https://raw.githubusercontent.com/OpenNeptune3D/OpenNept4une/main/img-config/printer-data/KAMP_Settings.cfg"]="KAMP_Settings.cfg"
    ["https://raw.githubusercontent.com/OpenNeptune3D/OpenNept4une/main/img-config/printer-data/adxl.cfg"]="adxl.cfg"  
)

# Destination directory
DEST_DIR="$HOME/printer_data/config"

# Loop through each link and download the file only if it doesn't exist
for link in "${!LINKS_AND_NAMES[@]}"; do
    FILENAME="${LINKS_AND_NAMES[$link]}"
    if [ ! -f "$DEST_DIR/$FILENAME" ]; then
        wget -O "$DEST_DIR/$FILENAME" "$link"
        echo "Downloaded $FILENAME."
    else
        echo "$FILENAME already exists. Skipping download."
    fi
done

# Change ownership of the config directory and its contents
chown -R "$SUDO_USER:$SUDO_USER" "$DEST_DIR"

# Fluidd DB transfer
SHARE_LINK="https://raw.githubusercontent.com/OpenNeptune3D/OpenNept4une/main/img-config/printer-data/data.mdb"

DESTINATION_DIR="$HOME/printer_data/database"
DESTINATION_FILE="${DESTINATION_DIR}/data.mdb"

# Check and create the output directory if it doesn't exist
[ ! -d "${DESTINATION_DIR}" ] && mkdir -p "${DESTINATION_DIR}"

# Download the .mdb file only if it doesn't already exist
if [ ! -f "${DESTINATION_FILE}" ]; then
    wget -O "${DESTINATION_FILE}" "${SHARE_LINK}"
    echo "Downloaded ${DESTINATION_FILE}."
else
    echo "${DESTINATION_FILE} already exists. Skipping download."
fi

# Change ownership of the database directory and its contents
chown -R "$SUDO_USER:$SUDO_USER" "$DESTINATION_DIR"

# Change ownership of the entire printer_data directory to the user who runs the script
chown -R "$SUDO_USER:$SUDO_USER" "$HOME/printer_data"

# System updates and cleanups
apt update 
apt install ustreamer git python3-numpy python3-matplotlib libatlas-base-dev libopenblas-dev -y
apt upgrade -y
apt clean -y
apt autoclean -y
apt autoremove -y
rm -rf /var/log/*

# Create gpio and spi groups if they don't exist (for led control v.1.1+ & ADXL SPI)
groupadd gpio || true && usermod -a -G gpio mks && echo 'SUBSYSTEM=="gpio", KERNEL=="gpiochip*", GROUP="gpio", MODE="0660"' | tee /etc/udev/rules.d/99-gpio.rules > /dev/null 
groupadd spiusers || true && usermod -a -G spiusers mks 

# Copy necessary files for spidev fix
cp "$HOME/OpenNept4une/img-config/spidev-fix/99-spidev.rules" /etc/udev/rules.d/

#sudo cp ~/OpenNept4une/img-config/spidev-fix/rockchip-fixup.scr /boot/dtb/rockchip/overlay/
#sudo cp ~/OpenNept4une/img-config/spidev-fix/rockchip-spi-spidev.dtbo /boot/dtb/rockchip/overlay/

sh -c 'echo "$(date +"%Y-%m-%d") - OpenNept4une-v0.1.x-ZNP-K1" > /boot/.OpenNept4une.txt'

# Add sync command to crontab if not exists
CRON_ENTRY="*/10 * * * * /bin/sync"
if ! (crontab -l 2>/dev/null | grep -q "/bin/sync"); then
    (crontab -l 2>/dev/null; echo "$CRON_ENTRY") | crontab -
    echo "Sync command added to the crontab to run every 10 minutes."
else
    echo "The sync command is already in the crontab."
fi

# Execute additional scripts
"$HOME/OpenNept4une/img-config/usb-storage-automount.sh"
"$HOME/OpenNept4une/img-config/adb-automount.sh"
"$HOME/OpenNept4une/display/display-service-installer.sh"

# Kernel RT/Timing fix 
echo "kernel.sched_rt_runtime_us = -1" | tee -a /etc/sysctl.d/10-disable-rt-group-limit.conf

# Immediate sync execution
sync

# Start Network Manager Text User Interface
nmtui

# Run kiauh.sh as the mks user
sudo -u mks "$HOME/kiauh/kiauh.sh"
