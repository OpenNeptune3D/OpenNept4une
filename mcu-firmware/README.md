# How to Read/Flash Neptune 4 MCU Firmware

**Warning:** Only flash this firmware on a DE-ELEGOO setup/image, **not** on stock Elegoo software.

## How to Flash Updated Klipper MCU Firmware:
(Only do this if you have the OpenNept4ne Image or have De-Elegood your machine)

1. **Update Klipper etc in Kiauh:**
   ```
   ~/kiauh/kiauh.sh
   ```
   - Select Menu Option 2
   - Wait for kiauh to check for updates
   - Type the letter 'a' to select update all
   - Press ENTER to initiate updates
   - Exit out of kiauh
  
2. **MicroSD Preparation:**
   - Format a MicroSD card to FAT32
   - Download this firmware file [X_4.bin](https://github.com/halfmanbear/OpenNept4une/raw/main/mcu-firmware/X_4.bin). Alternatively, compile the latest (INFO further down #Compile Latest klipper.bin)
   - Copy the file to the root of the MicroSD
   - Safely Eject the MicroSD
   - Backup your current MCU firmware (Optional: A standard Elegoo firmware-back.bin is provided in this repo so you don't have to make your own)
  
3. **Firmware Update:**
   - Ensure your printer is powered off
   - Insert the MicroSD into your printer (Internal access only on some variants)
   - Power on the printer and wait 2min
   - Check Fluidd's System tab for the updated klipper version [mcu Information v0.12.0-93]
   - If you read the MicroSD card from a computer you should see that X_4.bin has been renamed to X_4.CUR if it has been successfully updated

4. **Update MCU RPi (Virtual MCU):**
   - Run the main install script with,
   ```
   ~/OpenNept4une/OpenNept4une.sh
   ```
   - Select Menu Option 4: Install/Update (Virtual) MCU rpi Firmware
   - Read the Provided Instructions (in the script)
   - Your printer will then reboot
   - Check Fluidd's System tab for the updated klipper version [mcu rpi Information v0.12.xxx]

## If MicroSD update doesn't work (usually if you flashed MCU firmware before with the boot/reset method):**

. **Enter Bootloader Mode:**
   - Turn on the printer.
   - Simultaneously press and hold the BOOT button (or bridge the BOOT pads) and the RESET button.
   - First, let go of the RESET button and wait for about one second.
   - Then, release the BOOT button.
   - Then, flash the provided 0.12.0.93 firmware with:
     ```
     sudo service klipper stop
     stm32flash -w ~/OpenNept4une/mcu-firmware/12-093-full.bin -v /dev/ttyS0
     ```
   - Type `sudo poweroff` (then power cycle after ~20s).
   - Going forward you may use the first MicroSD method to update your MCU to the latest version.

## Backup MCU Klipper Firmware (Optional):

1. **Solder a Momentary Button:**
   - Solder a momentary push button on the BOOT pads on the MKS/Elegoo control board next to the RESET button. This button is a common 6x3x4.3 mm SMD Tactile Push Button Switch. 
   - Alternatively, the riskier method is to bridge these with sharp metal tweezers when required (not advised due to ESD & potential for short circuit).
   - ![boot reset location](../pictures/BOOTRESET.jpg)
   
2. **Power On and Boot Process:**
   - Ensure the printer is on.
   - Simultaneously press and hold the BOOT button (or bridge the BOOT pads) and the RESET button.
   - First, let go of the RESET button and wait for about one second.
   - Then, release the BOOT button.

3. **SSH and Commands:**
   - Leave the printer on, and SSH in (as mks) and type:
     ```
     sudo service klipper stop
     stm32flash -r ~/firmware-bak.bin /dev/ttyS0
     ```
   - If this errors out, repeat the BOOT/RESET button-press then re-run the stm32flash command till it works.

4. **Copy Firmware Backup off the Machine (Optional):**
   - From another terminal on the computer, copy this off your printer using:
     ```
     scp mks@IPADDRESS:/home/mks/firmware-bak.bin .
     ```

5. **Shutdown:**
   - Type `sudo poweroff` (then power cycle after ~20s).

## Compile Latest klipper.bin:

1. **Update Klipper etc in Kiauh:**
   ```
   ~/kiauh/kiauh.sh
   ```
   - Select Menu Option 2
   - Wait for kiauh to check for updates
   - Type the letter 'a' to select update all
   - Press ENTER to initiate updates
   - Exit out of kiauh

2. **SSH and Commands:**
   - Turn the printer on, SSH in (as mks) and type:
     ```
     cd ~/klipper && make clean && make menuconfig && make
     ```
   - Enter the following configurations using arrow keys and SPACEBAR to select.
   - STMicroelectronics STM32 - STM32F401 - 32KiB Bootloader - and USART PA10/PA9 - settings.
   - Once you have selected the correct options hit the Q key and then Y to close, save and compile.

3. **Download File to MicroSD:**
   - Move and rename the compiled klipper.bin with the following command
   ```
   cp ~/klipper/out/klipper.bin ~/printer_data/config/X_4.bin
   ```
   - In fluidd enter the Configuration tab (left edge)
   - You will find X_4.bin located within the Configuration Files
   - Right-click this file then click download
   - Format a MicroSD card to FAT32
   - Copy your Downloaded X_4.bin to the root of the MicroSD
   - Safely Eject the MicroSD
  
4 **Firmware Update:**
   - Ensure your printer is powered off
   - Insert the MicroSD into your printer
   - Power on the printer and wait 2min
   - Check Fluidd's System tab for the updated klipper version [mcu Information v0.12.xxx]
   - If you read the MicroSD card from a computer you should see that the X_4.bin has been renamed to X_4.CUR if it has been successfully updated

## How to Recover Original Elegoo MCU Firmware

(Your previously backed-up Elegoo Firmware or the backup in this repo)

1. **Power On and Boot Process:**
   - Similar to the above steps.
   
2. **SSH and Commands:**
   - Leave the printer on, and SSH in (as mks) and type:
     ```
     sudo service klipper stop
     stm32flash -w ~/firmware-bak.bin -v /dev/ttyS0
     ```
   - If you didn't make your own backup run
     ```
     sudo service klipper stop
     stm32flash -w ~/OpenNept4une/mcu-firmware/firmware-bak.bin -v /dev/ttyS0
     ```
   - If the stm32flash command fails [Failed to init device, timeout.], retry the BOOT & RESET button method above then re-run the stm32flash command till it works.
   - Type `sudo poweroff` (then power cycle after ~20s).



