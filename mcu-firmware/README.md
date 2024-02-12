# How to Flash the Latest Neptune 4 MCU Firmware

**Warning:** Only flash this firmware on a DE-ELEGOO setup/image, **not** on stock Elegoo software.

Accessing the [**Hidden microSD slot**](https://github.com/OpenNeptune3D/OpenNept4une/wiki/Hidden-microSD-Slot-Access) (later model N4+Pro & Plus / Max)

## How to Flash Updated Klipper MCU Firmware:
(Only do this if you have the OpenNept4ne Image or have De-Elegood your machine)

```
~/OpenNept4une/OpenNept4une.sh
```
- Select menu Option 4
- Then select option 4 `ALL`
- Note: if you don't have a pico accelerometer `Skip` this step when prompted.

## How to revert to Original Elegoo MCU Firmware

- Format a MicroSD card to FAT32
- Download this firmware file [**ElegooSD-restore.bin**](https://github.com/OpenNeptune3D/OpenNept4une/raw/dev/mcu-firmware/ElegooSD-restore.bin)
- Move the file to the root of the MicroSD, duplicate the file, name one X_4.bin, and the other elegoo_k1.bin
- Safely Eject the MicroSD
- Ensure your printer is powered off
- Insert the MicroSD into your printer 
- Power on the printer and wait 2min

More info in the [**Wiki**](https://github.com/OpenNeptune3D/OpenNept4une/wiki/)
