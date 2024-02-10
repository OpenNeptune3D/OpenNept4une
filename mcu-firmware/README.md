# How to Read/Flash Neptune 4 MCU Firmware

**Warning:** Only flash this firmware on a DE-ELEGOO setup/image, **not** on stock Elegoo software.

## How to Flash Updated Klipper MCU Firmware:
(Only do this if you have the OpenNept4ne Image or have De-Elegood your machine)

```
~/OpenNept4une/OpenNept4une.sh
```
- Select menu Option 4
- Then select option 4 `ALL`
- Note: if you dont have a pico accelerometer skip this step when prompted.

## How to revert to Original Elegoo MCU Firmware

1. **MicroSD Preparation:**
   - Format a MicroSD card to FAT32
   - Download this firmware file [ElegooSD-restore.bin](https://github.com/OpenNeptune3D/OpenNept4une/raw/dev/mcu-firmware/ElegooSD-restore.bin).
   - Move the file to the root of the MicroSD, duplicate the file and name one X_4.bin , and the other elegoo_K1.bin
   - Safely Eject the MicroSD
   -   
2. **Firmware Update:**
   - Ensure your printer is powered off
   - Insert the MicroSD into your printer (Internal access is required on some models: Remove 4 front hex bolts, bottom panel, then the 2 front panel mount screws. Cut a slot for future updates.)
   - Power on the printer and wait 2min
   - Check Fluidd's System tab for the updated klipper version [mcu Information v0.12.0-93]
   - If you read the MicroSD card from a computer you should see that X_4.bin (or elegoo_K1.bin) has been renamed to a (.CUR) if it has been successfully flashed.

## Notes

The default settings for the MCU image through Klipper's `make menuconfig` are as follows:
![Alt text](/pictures/flash.png)
