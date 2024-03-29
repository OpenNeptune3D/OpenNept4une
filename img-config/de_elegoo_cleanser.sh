#!/bin/bash

# User prompt for warning and confirmation
echo -e "WARNING: This script will significantly change your system's package sources and installed packages.\n\n"
echo -e "This can potentially BRICK this Armbian install.\n\n"
echo -e "Please ensure you understand the risks.\n"
echo -e "An eMMC reader will be required if it goes wrong. So consider just flashing the OpenNept4une Image"

echo -e "Do you wish to continue? (yes/no)"

# Read user input
read -r response

# Check if the user wants to proceed
if [[ "$response" != "yes" ]]; then
    echo -e "Operation aborted by the user."
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

sudo cp ~/OpenNept4une/img-config/led-v1.1+fix/99-gpio.rules /etc/udev/rules.d/

~/klipper/scripts/klipper-uninstall.sh
~/moonraker/scripts/uninstall-moonraker.sh
~/crowsnest/tools/uninstall.sh

sudo find /home/mks/ -mindepth 1 -path '/home/mks/OpenNept4une' -prune -o -exec rm -rf {} +

sudo rm -rf /root/*

sudo apt remove nginx -y

# TESTING Risky Bookworm Upgrade
# Hold DTB, u-boot, kernel & firmware packages
sudo apt-mark hold linux-dtb-edge-rockchip64 linux-image-edge-rockchip64 linux-libc-dev:arm64 linux-u-boot-mkspi-edge armbian-bsp-cli-mkspi armbian-firmware
# Update Buster packages
##sudo apt update -y && sudo apt upgrade -y && sudo apt autoremove -y
# Hold Armbian update sources before full-upgrade
# Update Buster sources to Bookworm
##sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/armbian.list
##sudo sed -i 's/buster/bookworm/g' /etc/apt/sources.list
##sudo sed -i 's/buster/bookworm/g' /etc/apt/sources.list.d/armbian.list
##echo "deb http://security.debian.org/debian-security bookworm/updates main contrib non-free" | sudo tee -a /etc/apt/sources.list
# Install Bookworm packages and perform a full upgrade
sudo apt update -y
# Release Armbian update sources after full-upgrade
sudo apt upgrade -y
##sed -i 's/^#deb/deb/' /etc/apt/sources.list.d/armbian.list

sudo apt autoremove -y
sync
#echo "Upgrade to Bookworm completed."

# Create the config directory structure if not exists
[ ! -d "$HOME/printer_data/config/" ] && mkdir -p ~/printer_data/config/

# Create the database directory structure if not exists
[ ! -d "$HOME/printer_data/database/" ] && mkdir -p ~/printer_data/database/

# Clone the KAMP git repository if not exists
if [ ! -d "$HOME/Klipper-Adaptive-Meshing-Purging" ]; then
    cd ~/ && git clone https://github.com/kyleisah/Klipper-Adaptive-Meshing-Purging.git
fi

# Create a symbolic link if not exists
[ ! -L "$HOME/printer_data/config/KAMP" ] && ln -s ~/Klipper-Adaptive-Meshing-Purging/Configuration ~/printer_data/config/KAMP

# Clone Kiauh git repository if not exists
if [ ! -d "$HOME/kiauh" ]; then
    cd ~/ && git clone https://github.com/dw-0/kiauh.git
fi

# Pick Legacy Crowsnest
cd ~/ && git clone --branch legacy/v3 https://github.com/mainsail-crew/crowsnest.git
cd ~/crowsnest && sudo make install >/dev/null 2>&1 &
echo -e "installing crowsnest"
sleep 60

FILE="$HOME/printer_data/config/moonraker.conf"

perl -i -pe 'if (/^\[update_manager crowsnest\]/ ... /^$/) {
    if (/origin: https:\/\/github\.com\/mainsail-crew\/crowsnest\.git/) {
        print;
        print "primary_branch: legacy/v3\n";
    } else {
        print;
    }
}' "$FILE"
echo "File updated successfully."

sudo apt install network-manager -y 
sudo apt install ustreamer -y 
sudo apt install python3-venv -y 
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

# Copy Configurations
cp -r ~/OpenNept4une/img-config/printer-data/* ~/printer_data/config/ && \
mv ~/printer_data/config/data.mdb ~/printer_data/database/data.mdb

sudo rm /usr/lib/udev/rules.d/60-usbmount.rules
sudo rm /usr/lib/udev/rules.d/99-makerbase-automount.rules

sudo nmtui

clear

echo -e "When Kiauh opens after these instructions, go to the uninstall page FIRST and remove the following for final clean-up.\n"
echo -e "even if they don't look installed... (Klipper, Moonraker, fluidd, fluid-config & klipper-screen)\n"
echo ""
echo -e "Then Install the following, in this ORDER.\n"
echo -e "Klipper, Moonraker, Fluidd, Mainsail (on port 81) then Mobileraker (No others for now).\n"
echo -e "After, on the main kiauh menu select Update then all with (a)\n"
echo -e "then exit kiauh\n"
echo ""
echo -e "You should then run ~/OpenNept4une/OpenNept4une.sh\n"
echo -e "The main requirement here is to Install the latest OpenNept4une configurations (Option 1)\n" 
echo -e "Select No (n) when asked to reboot then select - Update MCU & (Virtual) MCU rpi Firmware.\n"
echo -e "Copy / screenshot the text above for reference as it will disappear.\n"
echo ""
echo -e "Press Enter when you are ready to continue..."
read -r

sync 

# Run kiauh.sh as the mks user
~/kiauh/kiauh.sh
