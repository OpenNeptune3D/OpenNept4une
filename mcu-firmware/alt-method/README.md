# How to Dump/Flash Neptune 4 MCU Firmware

**Warning:** Only flash this firmware on a DE-ELEGOO setup/image, **not** on stock Elegoo software.

## Steps:

1. **Solder/Wire bridge the following two sets of jumper pads (This is ZNP-K1 v1.0 pad locations will differ on other revisions):**\
![Alt text](/pictures/pads-bridge.jpg)

3. **Run SoftwareFlash Install Script then reboot:**

   ```
   ./mcu-swflash-install.sh
   ```

4. **Run SoftwareFlash Script - ideally copy the provided v0.12 klipper.bin (above) to the same directory and flash this when prompted - After this flash you may continue with the configurations below for future releases:**

   ```
   ./mcu-swflash-run.sh
   ```
      
![Alt text](/pictures/flash.png)





