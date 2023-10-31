# OpenNept4une
De Elegoo-izing the Neptune 4 / Pro (Both 0.8A & 1.2A Versions) & MAX

NOTE the Elegoo touchscreen will not be functional after this.

Image Features:

Armbian 23.08.0-trunk Bookworm with bleeding edge Linux 6.5.9-edge-rockchip64 (Credit: https://github.com/redrathnure/armbian-mkspi)
Elegoo Services Removed (No Z-Axis Issues)
KAMP configured and Installed (Creates a smaller, print area localised bed level mesh before each print + Smart Park + Line Purge) https://github.com/kyleisah/Klipper-Adaptive-Meshing-Purging
Bed Leveling Macros (Bed Screw Tuning macro, Z Probe Calib & Auto Full Bed Mesh)
PID Calibration Macros (Extruder + Improved for both heated bed segments)
Easy WiFi config
Working segmented bed heaters (N4Pro) - also configurable
Armbian packages updated (as of Oct 2023) 
No need for Elegoo Firmware Updates going forward (Stock Klipper etc Updated in Fluidd GUI or Kiauh)
Crowsnest Current (Main) w/ ustreamer 
Orca Slicer Profiles Provided
Simplified printer.cfg 
(Credit: Modified SmartHome42/Printernbeer & Tom's Basement Neptune 4 Config)
Renamed variables to make it easier to read
Corrected instructions for Flashing v0.11 Klipper MCU Firmware 
Firmware Retraction configured
Removed MCU PI
E & Z Steppers configured for 64 microsteps / Interpolation Disabled & stealthChop disabled (Results in higher accuracy without sacrificing much stepper torque)
X & Y Steppers remain at 16 microsteps with Interpolation enabled & stealthChop enabled (16 microsteps with interpolation is a common setting, providing a balance of torque and resolution and low noise)
Mellow Fly-ADXL345 USB Accelerometer configuration included [include adxl.cfg]


Installed Services (Clean Official) - Current as of OCT 2023:
Klipper v0.11.0-304-gf7567a0d
moonraker v0.8.0-188-ga71c5c15
Klipper-Adaptive-Meshing-Purging v1.1.2-4-g2389a994
fluidd v1.26.1
fluidd-config v0.0.0-9-gfcf0d445-inferred
mainsail v2.8.0 (Configured on port 81)
mainsail-config v1.0.0-16-gc64d3af9
crowsnest v4.0.4-6-g767c53aa
mobileraker v0.4.0-29-g5a4cae4a


