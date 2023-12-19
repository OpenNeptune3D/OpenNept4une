# OpenNept4une

## De-Elegoo-izing the Neptune 4 Series 3D Printers

**NOTE: The touch-screen will not be functional after this!**  
**LED’s, ADXL & WiFi Working on all Variants**

**Credits:**
- Community Members: SQUIRRELYMOOSE, DanDonut, Jaerax, SmartHome42/Printernbeer & Tom's Basement
- Projects: 
  - Armbian: [GitHub](https://github.com/armbian/build)
  - (Fork) Armbian-ZNP-K1-build base image: [GitHub](https://github.com/halfmanbear/Armbian-ZNP-K1-build)
  - KAMP (Klipper-Adaptive-Meshing-Purging): [GitHub](https://github.com/kyleisah/Klipper-Adaptive-Meshing-Purging)
  - kiauh (Klipper Installation And Update Helper): [GitHub](https://github.com/dw-0/kiauh)
  - Klipper: [GitHub](https://github.com/Klipper3d/klipper)
  - moonraker: [GitHub](https://github.com/Arksine/moonraker)
  - fluidd: [GitHub](https://github.com/fluidd-core/fluidd)
  - mainsail: [GitHub](https://github.com/mainsail-crew/mainsail)
  - crowsnest: [GitHub](https://github.com/mainsail-crew/crowsnest)
  - mobileraker: [GitHub](https://github.com/Clon1998/mobileraker)

### Image Features

- Armbian 24.02.0-trunk Bookworm with Linux 6.1.67-current-rockchip64 ([Credit](https://github.com/halfmanbear/Armbian-ZNP-K1-build))
- Elegoo Services Removed (No Z-Axis Issues)
- KAMP configured and installed
- Bed Leveling Macros
- Axis_Twist_Comp_Tune - Macro ([Klipper Docs](https://www.klipper3d.org/Axis_Twist_Compensation.html))
- PID Calibration Macros
- Easy WiFi config
- Working segmented bed heaters (N4Pro)
- Armbian packages updated (as of Dec 2023)
- No need for Elegoo Firmware Updates (Updated in Fluidd GUI or Kiauh)
- Crowsnest Current (Main) w/ ustreamer
- Orca Slicer Profiles Provided
- Simplified printer.cfg (Credit: Modified SmartHome42/Printernbeer & Tom's Basement Neptune 4 Config)
- Renamed variables for readability
- Corrected instructions for Flashing v0.12 Klipper MCU Firmware
- Firmware Retraction configured
- E & Z Steppers configured for 32 microsteps
- X & Y Steppers at 16 microsteps with Interpolation and stealthChop enabled
- SPI ADXL345 & Mellow Fly-ADXL345 USB Accelerometer configuration included

## Install Procedure - Re-flash eMMC with Latest OpenNept4une Release Image

**Requirements:**
- Makerbase MKS EMMC-ADAPTER V2 USB 3.0 Reader For MKS EMMC Module: [AliExpress](https://www.aliexpress.com/item/1005005614719377.html)
- Alternatively, a spare eMMC & eMMC > microSD adapter: [AliExpress](https://www.aliexpress.com/item/1005005549477887.html)

## Printer Terminal Access Options:
Terminal / Shell access via SSH (Requires ethernet connection) -\
    \
    ssh mks@printer ip\
    Password = makerbase\
    User: root can login via - root:makerbase\ (not advised)
    \
    ---\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\--\
    \
    PuTTY / Serial terminal access (Without Ethernet) -\
    \
    Connect N4P USB-C port to PC Then connect via Serial COM8 (yours
    will be different) set baudrate to 1500000\
    \
    User: mks\
    Pass: makerbase\
    \
    ---\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\---

**Installation:**
- See the [Releases](https://github.com/halfmanbear/OpenNept4une/releases/) section for the latest pre-configured OpenNept4une eMMC Image. Flash with balenaEtcher or dd.
- Recommended to Back-Up original eMMC beforehand.
- Run the following startup script (as user mks) to load the correct machine and printer.cfg
```bash
chmod +x ~/OpenNept4une/OpenNept4une.sh && cd ~/OpenNept4une; git pull origin main; ~/OpenNept4une/OpenNept4une.sh
``` 
- Be sure to check the latest printer.cfg for your model here [printer-confs](https://github.com/halfmanbear/OpenNept4une/tree/main/printer-confs/).
- If you have a v1.1 N4/Pro, delete LED Control v1.0 in your new printer.cfg & un-comment v1.1 LED section.
- A force update of the git repo might be required once your network is configured (you may re-run the above afterwards).
```bash
cd ~/OpenNept4une/ && git reset --hard && git clean -fd && git pull origin main --force
```
# General Configuration Instructions

Follow these steps to configure the basic settings on your Neptune 4 printer's custom Armbian image:

## Configure Correct Timezone

1. **Access Armbian Configuration:**
   Open the terminal and enter the following command:
```bash
  sudo armbian-config
```
2. **Set Timezone:**
- Navigate to `Personal`.
- Then select `Timezone`.
- Choose and set your correct timezone.

## Configure Wi-Fi

1. **Access Network Manager:**
Use the following command in the terminal to open the network manager:
```bash
  sudo nmtui
```
2. **Connect to Wi-Fi:**
- In the network manager, navigate to `Activate a connection`.
- Select your Wi-Fi network and enter the necessary credentials to connect.

Remember to save your settings before exiting any configuration menus. 

### OrcaSlicer Configs 
- Download the latest Official Release [OrcaSlicer](https://github.com/SoftFever/OrcaSlicer/releases/) 
- Configure Orca defaults for your machines model before import.
- Check/confirm Bambu Network Engine install
- Download the latest [OrcaSlicer Profiles](https://github.com/halfmanbear/OpenNept4une/tree/main/orca-profiles)
- In OrcaSlicer click [File > Import > Import Configs...]


## Fluidd / Klipper Calibration: -

Config / Tuning Macros below (found pre-configured in Fluidd \|
BedTune/Level macros will begin after heating- do Probe Z Offset
cold):\
\
------------------------------------\
\
    BED_LEVEL_SCREWS_TUNE\
    [[Klipper Docs](https://www.klipper3d.org/Manual_Level.html#adjusting-bed-leveling-screws-using-the-bed-probe)]
    (Rerun macro after each round of corrections)\
    \
    CALIBRATE_PROBE_Z_OFFSET\
    (Paper Thickness Test. When you determine a value, click Accept and
    run a SAVE_CONFIG command after)\
    \
    AUTO_FULL_BED_LEVEL\
    (Not required as using KAMP meshes before print, but useful
    to see how level the whole bed is - Click Save Config & Restart
    after)\
    \
    ---\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\--\
    \
    **(Note: Do each of these separately and from a low temp not whilst
    hot if Non-Pro only do the inner bed PID macro after tuning
    the extruder)**\
    \
    PID_TUNE_EXTRUDER\
    PID_TUNE_INNER_BED\
    PID_TUNE_OUTER_BED\
    \
    ---\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\--\
    \
    Pressure advance value will need your own data.\
    [<https://www.klipper3d.org/Pressure_Advance.html>]\
    \
    Input shaping values will also need your own data\
    [<https://www.klipper3d.org/Resonance_Compensation.html>]\
    (SPI ADXL345 & Mellow Fly-ADXL345 Pre Configured for tuning)\
    \
    After editing configs or calibrating, save in the fluidd
    interface, then in fluidd select the top right menu \> Host \>
    reboot. Avoid direct power cycles; this ensures changes are saved from
    RAM to eMMC.
    
## Slicer Settings 
(If using the provided OrcaSlicer profiles you can skip
    this - also only relevant to n4pro model with the zoned bed heaters)\
    \
    ---\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\--\
    \
    **Slicer START CODE (OrcaSlicer)**
    \
    NOTE all text including PRINT_START and after must be on one line

    

```
    ;Nozzle diameter = [nozzle_diameter]
    ;Filament type = [filament_type]
    ;Filament name = [filament_vendor] 
    ;Filament weight = [filament_density]
    PRINT_START BED_TEMP=[hot_plate_temp_initial_layer] EXTRUDER_TEMP=[nozzle_temperature_initial_layer] AREA_START={first_layer_print_min[0]},{first_layer_print_min[1]} AREA_END={first_layer_print_max[0]},{first_layer_print_max[1]}
```
 \
 \
    ---\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\--\
    \
    **Slicer PRINT END CODE (Use for all Slicers)**\
    \
    ```
    PRINT_END
    ```
    \
    \
    ---\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\--\
    \
    **Slicer START CODE (PrusaSlicer)**
    \
    NOTE all text including PRINT_START and after must be on one line
    
    
```
    ;Nozzle diameter = [nozzle_diameter]
    ;Filament type = [filament_type]
    ;Filament name = [filament_vendor]
    ;Filament weight = [filament_density]
    PRINT_START BED_TEMP=[first_layer_bed_temperature] EXTRUDER_TEMP=[first_layer_temperature] AREA_START={first_layer_print_min[0]},{first_layer_print_min[1]} AREA_END={first_layer_print_max[0]},{first_layer_print_max[1]}
```
\
    \
    ---\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\--\
    
