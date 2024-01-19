#!/bin/bash

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

sudo cp /home/mks/OpenNept4une/img-config/spidev-fix/rockchip-spi-spidev.dtbo /boot/dtb/rockchip/overlay/
sudo cp /home/mks/OpenNept4une/img-config/spidev-fix/rockchip-spi-spidev.dtbo /boot/dtb-5.16.20-rockchip64/rockchip/overlay/

sudo cp /home/mks/OpenNept4une/img-config/spidev-fix/rockchip-fixup.scr /boot/dtb/rockchip/overlay/
sudo cp /home/mks/OpenNept4une/img-config/spidev-fix/rockchip-fixup.scr /boot/dtb-5.16.20-rockchip64/rockchip/overlay/

sudo cp /home/mks/OpenNept4une/img-config/spidev-fix/99-spidev.rules /etc/udev/rules.d/
sudo cp /home/mks/OpenNept4une/img-config/led-v1.1+fix/99-gpio.rules /etc/udev/rules.d/

/boot/dtb-5.16.20-rockchip64/rockchip/overlay/
/boot/dtb-5.16.20-rockchip64/rockchip/

/home/mks/klipper/scripts/klipper-uninstall.sh
/home/mks/moonraker/scripts/uninstall-moonraker.sh
/home/mks/crowsnest/tools/uninstall.sh

sudo find /home/mks/ -mindepth 1 ! -path '/home/mks/OpenNept4une*' -exec rm -rf {} +
sudo rm -rf /root/*

# Create the config directory structure if not exists
[ ! -d "/home/mks/printer_data/config/" ] && mkdir -p /home/mks/printer_data/config/

# Clone the KAMP git repository if not exists
if [ ! -d "/home/mks/Klipper-Adaptive-Meshing-Purging" ]; then
    cd /home/mks
    git clone https://github.com/kyleisah/Klipper-Adaptive-Meshing-Purging.git
fi

# Create a symbolic link if not exists
[ ! -L "/home/mks/printer_data/config/KAMP" ] && ln -s /home/mks/Klipper-Adaptive-Meshing-Purging/Configuration /home/mks/printer_data/config/KAMP

# Clone Kiauh git repository if not exists
if [ ! -d "/home/mks/kiauh" ]; then
    cd /home/mks
    git clone https://github.com/dw-0/kiauh.git
fi

# Hardcoded list of GitHub raw links paired with filenames
declare -A LINKS_AND_NAMES=(
    ["https://raw.githubusercontent.com/halfmanbear/OpenNept4une/main/img-config/printer-data/printer.cfg"]="printer.cfg"
    ["https://raw.githubusercontent.com/halfmanbear/OpenNept4une/main/img-config/printer-data/moonraker.conf"]="moonraker.conf"
    ["https://raw.githubusercontent.com/halfmanbear/OpenNept4une/main/img-config/printer-data/KAMP_Settings.cfg"]="KAMP_Settings.cfg"
    ["https://raw.githubusercontent.com/halfmanbear/OpenNept4une/main/img-config/printer-data/adxl.cfg"]="adxl.cfg"  
    ["https://raw.githubusercontent.com/halfmanbear/OpenNept4une/main/img-config/printer-data/crowsnest.conf"]="crowsnest.conf"
)

# Destination directory
DEST_DIR="/home/mks/printer_data/config"

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

# Fluidd DB transfer
SHARE_LINK="https://raw.githubusercontent.com/halfmanbear/OpenNept4une/main/img-config/printer-data/data.mdb"

DESTINATION_DIR="/home/mks/printer_data/database"
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

sudo apt-mark hold linux-dtb-edge-rockchip64 linux-image-edge-rockchip64 linux-libc-dev:arm64 linux-u-boot-mkspi-edge armbian-bsp-cli-mkspi armbian-firmware

sudo apt update 
sudo apt remove nginx -y
sudo apt install network-manager -y 
sudo apt install ustreamer -y 
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

clear

echo "When Kiauh opens, go to the uninstall page FIRST and remove each one for final clean-up"
echo "even if they don't look installed..."
sleep 5
echo ""
echo "Then Install the following, in this ORDER."
echo "Klipper, Moonraker, Fluidd, Mainsail (on port 81), Mobileraker then Crowsnest"
echo ""
echo "You should then run chmod +x ~/OpenNept4une/OpenNept4une.sh && ~/OpenNept4une/OpenNept4une.sh"
echo ""
echo "The main requirement here is to install the latest printer.cfg"
echo ""
echo "Copy the text above for reference as it will disappear in 20s"

countdown=20

while [ $countdown -gt 0 ]; do
    if (( $countdown % 5 == 0 )); then
        echo "Waiting for $countdown seconds..."
    fi

    sleep 1
    ((countdown--))
done

echo "Countdown finished."

sync 

# Run kiauh.sh as the mks user
sudo -u mks /home/mks/kiauh/kiauh.sh
