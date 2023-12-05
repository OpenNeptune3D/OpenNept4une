# How to Dump/Flash Neptune 4 MCU Firmware

**Warning:** Only flash this firmware on a DE-ELEGOO setup/image, **not** on stock Elegoo software.

## Steps:

1. **Solder/Wire bridge the following two sets of jumper pads (with machine off):**\
![Alt text](/pictures/pads-bridge.jpg)

3. **Run SoftwareFlash Install Script then reboot:**

   ```
   ./mcu-swflash-install.sh
   ```

4. **Run SoftwareFlash Script ideally copy the klipper.bin here to the same directory and flash that when prompt after this flash you may continue with the configurations below going forward:**

   ```
   ./mcu-swflash-run.sh
   ```
      
![Alt text](/pictures/flash.png)





