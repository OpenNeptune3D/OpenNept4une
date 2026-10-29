# n4flash

Flashes the USB-C toolhead through its MKS bootloader (USB `1d50:018a`,
`/dev/serial/by-id/usb-MKS_DRIVER_BOOT_*`). Written by ggggcodes, who
reverse engineered the bootloader protocol: <https://codeberg.org/gggcodes/n4flash>
(MIT, see `LICENSE`).

`n4flash.c` is an unmodified copy of upstream commit
`686c3bf1d0ea5f98d991ea56a3f5a35944f300fd`
(SHA-256 `fed0708f556462a6d02aba6627237b42bcdaffc3bbafde34751dbc1602f2cb2d`),
the version tested on real toolheads. Fix protocol issues upstream and re-vendor,
rather than patching this copy.

`img-config/rpi-mcu-install.sh` compiles it on the printer and adds the checks
around it: the firmware must fit the 96 KiB application region, exactly one
bootloader device must be present, and success means the Klipper application
re-enumerates afterwards.

The bootloader erases the toolhead application when a transfer starts. If a
flash is interrupted, the toolhead should stay in the bootloader, and the update can
simply be run again.
