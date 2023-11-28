# OpenNept4une

## De-Elegoo-izing the Neptune 4 / Pro (Both 0.8A & 1.2A Versions)
**NOTE the touch-screen will not be functional after this!**

### Image Features

-   Armbian 23.08.0-trunk Bookworm with bleeding edge Linux
    6.5.9-edge-rockchip64
    \
    (**Credit:** [<https://github.com/redrathnure/armbian-mkspi>])
-   Elegoo Services Removed (No Z-Axis Issues)
-   KAMP configured and Installed (Creates a smaller, print area
    localised bed level mesh before each print + Smart Park + Line
    Purge)
    [<https://github.com/kyleisah/Klipper-Adaptive-Meshing-Purging>]
-   Bed Leveling Macros (Bed Screw Tuning macro, Z Probe Calib & Auto
    Full Bed Mesh)
-   PID Calibration Macros (Extruder + Improved for both heated bed
    segments)
-   Easy WiFi config
-   Working segmented bed heaters (N4Pro) - also configurable
-   Armbian packages updated (as of Oct 2023)
-   No need for Elegoo Firmware Updates going forward (Stock Klipper etc
    Updated in Fluidd GUI or Kiauh)
-   Crowsnest Current (Main) w/ ustreamer
-   Orca Slicer Profiles Provided
-   Simplified printer.cfg\
    (**Credit**: Modified SmartHome42/Printernbeer & Tom\'s Basement
    Neptune 4 Config)
-   Renamed variables to make it easier to read
-   Corrected instructions for Flashing v0.11 Klipper MCU Firmware
-   Firmware Retraction configured
-   E & Z Steppers configured for 32 microsteps / Interpolation Disabled
    & stealthChop disabled (Results in higher accuracy without
    sacrificing much stepper torque)
-   X & Y Steppers remain at 16 microsteps with Interpolation enabled &
    stealthChop enabled (16 microsteps with interpolation is a common
    setting, providing a balance of torque and resolution and low noise)
-   Mellow Fly-ADXL345 USB Accelerometer configuration included
    \[include adxl.cfg\]
    
    
  ### Installed Services (Clean/Official) - *Current as of NOV 2023:
  
-   Klipper
-   moonraker 
-   Klipper-Adaptive-Meshing-Purging 
-   fluidd 
-   mainsail(Configured on port 81)
-   crowsnest 
-   mobileraker 


  ## Install Procedure - Re-flash eMMC with Latest OpenNept4une Release Image
  
Requires - Makerbase MKS EMMC-ADAPTER V2 USB 3.0 Reader For MKS EMMC Module\
[[https://www.aliexpress.com/item/1005005614719377.html](https://www.aliexpress.com/item/1005005614719377.html?spm=a2g0o.productlist.main.1.1c772487NAFecQ&algo_pvid=d021b499-e67b-4da5-8975-3bb0653bc16e&algo_exp_id=d021b499-e67b-4da5-8975-3bb0653bc16e-0&pdp_npi=4@dis!GBP!6.08!6.08!!!7.19!!@210318c916965901078338141e8cb7!12000033755356288!sea!UK!801158356!&curPageLogUid=tivQjvYHp000)]\
\
Alternatively, a spare eMMC & eMMC \> microSD adapter can be purchased (Preferred as can retain the original eMMC as an Elegoo Official loaded backup.\
[<https://www.aliexpress.com/item/1005005549477887.html>]\

**See the [Releases](https://github.com/halfmanbear/OpenNept4une/releases/tag/v0.1.3) section for the latest pre-configured OpenNept4une eMMC Image (flash with balenaEtcher or dd). Recommended to Back-Up original eMMC beforehand.**

Configured default for N4Pro 1.2A (see Printer Configs folder for one to match your model).\
\
OrcaSlicer Configs: (For N4P configure Orca defaults for your model printer before import) - (Remove reference to the Pro if trying to
import for a standard Neptune 4 or PLUS / MAX profile)

## Fluidd / Klipper Calibration: -

Config / Tuning Macros below (found pre-configured in Fluidd \|
BedTune/Level macros will begin after heating- do Probe Z Offset
cold):\
\
------------------------------------\
\
    BED_LEVEL_SCREWS_TUNE\
    [[https://www.klipper3d.org/Manual_Level.html#adjusting-bed-leveling-screws-using-the-bed-probe](https://www.klipper3d.org/Manual_Level.html%23adjusting-bed-leveling-screws-using-the-bed-probe)]\
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
    (Mellow Fly-ADXL345 Pre Configured for tuning)\
    \
    After editing configs or calibrating, save in the fluidd
    interface, then in fluidd select the top right menu \> Host \>
    reboot. Avoid direct power cycles; this ensures changes are saved from
    RAM to eMMC.
    
## Slicer Settings
(If using the provided OrcaSlicer profiles (for N4P) you can skip
    this)\
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
    \
    **Slicer START CODE (Cura)**
    \
    NOTE all text including PRINT_START and after must be on one line
    
    
```
    ;Nozzle diameter = {machine_nozzle_size}
    ;Filament type = {material_type}
    ;Filament name = {material_brand}
    ;Filament weight = {material_density}
    PRINT_START BED_TEMP={material_bed_temperature_layer_0} EXTRUDER_TEMP={material_print_temperature_layer_0} AREA_START={print_min_x},{print_min_y} AREA_END={print_max_x},{print_max_y}
```
\
    \
        ---\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\--
    
    
## Printer Terminal Access Options:
Terminal / Shell access via SSH (Requires ethernet connection) -\
    \
    ssh root@printer ip\
    Password = makerbase\
    User: mks is a sudoer also and can login via - mks:makerbase\
    \
    ---\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\--\
    \
    PuTTY / Serial terminal access (Without Ethernet) -\
    \
    Connect N4P USB-C port to PC Then connect via Serial COM8 (yours
    will be different) set baudrate to 1500000\
    \
    User: root\
    Pass: makerbase\
    \
    ---\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\-\---
