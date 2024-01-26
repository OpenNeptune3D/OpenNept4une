# How to Dump/Flash Neptune 4 MCU Firmware (Alternative Method)

**Warning:** This guide is specifically for ZNP-K1 V1.0 Boards. It may be similar for V1.1 boards without WiFi, but you will need to manually verify continuity and pinout to pads. Do **not** attempt to flash this firmware on a stock Elegoo setup; it is intended only for DE-ELEGOO images.

## Steps:

1. **Prepare the Board:**
   Solder a wire bridge across the specified jumper pads for the ZNP-K1 V1.0 board as shown in the image below. Note that this configuration has not been tested with boards that have integrated WiFi or are of the V2.0 revision.

   ![Soldering Jumper Pads](/pictures/pads-bridge-version10.jpg)

   _Note: After bridging and powering on the board for the first time, it will not communicate with Klipper. This is expected and will be resolved in the subsequent steps._

2. **Execute the Flashing Script:**
   Run the `mcu-swflash-install.sh` script and then reboot the system:

   ```
   ./mcu-swflash-install.sh
   ```

   _This script prepares the MCU board to boot in normal mode for regular operation. Post-reboot, the board will establish communication with Klipper._

3. **Update the MCU Firmware:**
   Execute the `OpenNept4une.sh` script to update your firmware:
   ```
   ./OpenNept4une.sh
   ```
   _The script will automatically detect the board version and apply the appropriate flashing procedure._

**Note:** Always ensure you are working in a safe environment when dealing with electronics and follow proper ESD precautions.
