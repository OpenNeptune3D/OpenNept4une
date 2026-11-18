# OpenNept4une UART DMA fix (OpenNept4une#444)
#
# Armbian's boot.scr sources /boot/fixup.scr after loading the DTB. This removes the
# DMA channels from the Klipper MCU UART (uart0, serial@ff110000) so the kernel falls
# back to interrupt-driven transfers. Linux 6.14-6.17 can deadlock UART TX DMA, which
# Klipper reports as "Lost communication with MCU", "Timer too close" or "Missed
# scheduling of next digital out event". Fixed upstream by a424a34b8fad (6.18.y, 7.0+).
#
# Build:  mkimage -C none -A arm -T script -n "OpenNept4une UART DMA fix" -d fixup.cmd fixup.scr
# Undo:   delete /boot/fixup.scr and reboot.

if fdt get value znp_uart_dma /serial@ff110000 dma-names; then
	fdt rm /serial@ff110000 dmas
	fdt rm /serial@ff110000 dma-names
	echo "OpenNept4une: disabled DMA on serial@ff110000 (Klipper MCU UART)"
fi
