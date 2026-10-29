# shellcheck shell=bash
# One-off system fixes applied on every run.
# Sourced by OpenNept4une.sh; defines functions (and the constants they use) only.

run_fixes() {
    # Get current user dynamically instead of hardcoding 'mks'
    CURRENT_USER="${USER:-$(whoami)}"
    
    # Add current user to 'gpio' and 'spiusers' groups for GPIO and SPI access
    if ! sudo usermod -aG gpio,spiusers "$CURRENT_USER" &>/dev/null; then
        printf '%s\n' "${R}Failed to add user '$CURRENT_USER' to groups 'gpio' and 'spiusers'${NC}"
    fi

    # Ensure NetworkManager override for Wi-Fi power-save exists
    NM_CONF_DIR="/etc/NetworkManager/conf.d"
    NM_PS_FILE="${NM_CONF_DIR}/zz-20-override-wifi-powersave-disable.conf"
    if [ ! -f "$NM_PS_FILE" ]; then
        if ! sudo mkdir -p "$NM_CONF_DIR"; then
            printf '%s\n' "${R}Failed to create $NM_CONF_DIR${NC}"
        elif ! sudo tee "$NM_PS_FILE" >/dev/null <<'EOF'
[connection]
wifi.powersave = 2
EOF
        then
            printf '%s\n' "${R}Failed to create $NM_PS_FILE${NC}"
        else
            sudo systemctl restart NetworkManager >/dev/null 2>&1
        fi
    fi

    # Remove obsolete GPIO script if it exists
    if [ -f "/usr/local/bin/set_gpio.sh" ]; then
        if ! sudo rm -f "/usr/local/bin/set_gpio.sh"; then
            printf '%s\n' "${R}Failed to remove /usr/local/bin/set_gpio.sh${NC}"
        fi
    fi

    # Ensure the flag file exists to mark completion of fixes
    if ! sudo touch "$FLAG_FILE"; then
        printf '%s\n' "${R}Failed to ensure flag file exists at $FLAG_FILE${NC}"
    fi

    # Append system information to the flag file if not already present
    SYSTEM_INFO=$(uname -a)
    if ! sudo grep -qF "$SYSTEM_INFO" "$FLAG_FILE" 2>/dev/null; then
        if ! echo "$SYSTEM_INFO" | sudo tee -a "$FLAG_FILE" >/dev/null; then
            printf '%s\n' "${R}Failed to append system info to $FLAG_FILE${NC}"
        fi
    fi

    # Create a symbolic link for OpenNept4une Logo in fluidd
    ln -sf "${HOME}/OpenNept4une/pictures/logo_opennept4une.svg" "${HOME}/fluidd/logo_opennept4une.svg" > /dev/null 2>&1

    # Create a symbolic link to the main script if it doesn't exist
    SYMLINK_PATH="/usr/local/bin/opennept4une"
    if [ ! -L "$SYMLINK_PATH" ]; then
        if ! sudo ln -sf "$SCRIPT" "$SYMLINK_PATH"; then
            printf '%s\n' "${R}Failed to create symlink at $SYMLINK_PATH${NC}"
        fi
    fi

    # Add /bin/sync to crontab if not present
    if ! (crontab -l 2>/dev/null | grep -q "/bin/sync"); then
        (crontab -l 2>/dev/null | grep -v '/bin/sync'; echo "*/10 * * * * /bin/sync") | crontab -
    fi

    # Create a power_monitor.service if not present
    if [ ! -f "/etc/systemd/system/power_monitor.service" ]; then
        sudo tee "/etc/systemd/system/power_monitor.service" > /dev/null <<EOF
[Unit]
Description=Power Cut Monitor and Safe Shutdown

[Service]
Type=simple
ExecStart=${HOME}/OpenNept4une/img-config/power_monitor.sh
User=root
Restart=no

[Install]
WantedBy=multi-user.target
EOF
        sudo systemctl daemon-reload > /dev/null 2>&1
        sudo systemctl enable power_monitor.service > /dev/null 2>&1
        sudo systemctl start power_monitor.service > /dev/null 2>&1
    fi

    # Make systemd-logind ignore power key / long press (silent, idempotent)
    LOGIND_CONF="/etc/systemd/logind.conf"
    if [ -f "$LOGIND_CONF" ]; then
        if ! sudo grep -q '^HandlePowerKey=ignore$' "$LOGIND_CONF" || \
           ! sudo grep -q '^HandlePowerKeyLongPress=ignore$' "$LOGIND_CONF"; then
            sudo cp "$LOGIND_CONF" "${LOGIND_CONF}.bak" 2>/dev/null || true
            sudo sed -i 's/^[#]*HandlePowerKey=.*/HandlePowerKey=ignore/' "$LOGIND_CONF" 2>/dev/null || true
            sudo sed -i 's/^[#]*HandlePowerKeyLongPress=.*/HandlePowerKeyLongPress=ignore/' "$LOGIND_CONF" 2>/dev/null || true
            sudo systemctl restart systemd-logind >/dev/null 2>&1 || true
        fi
    fi

    install_uart_dma_fix
    sync_toolhead_power
}

# U-Boot fixup that disables DMA on the Klipper MCU UART (OpenNept4une#444).
UART_DMA_FIX_SRC="${HOME}/OpenNept4une/img-config/uart-dma-fix/fixup.scr"
UART_DMA_FIX_DEST="/boot/fixup.scr"
UART_DMA_FIX_BOOT_SCR="/boot/boot.scr"
UART_DMA_FIX_NODE="/proc/device-tree/serial@ff110000"
UART_DMA_FIX_MARKER="OpenNept4une UART DMA fix"

# Linux 6.14-6.17 can deadlock UART TX DMA; 6.18.y and 7.0+ carry the upstream fix.
uart_dma_deadlock_kernel() {
    local ver major minor
    ver=$(uname -r)
    major=${ver%%.*}
    minor=${ver#*.}
    minor=${minor%%.*}
    [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] || return 1
    [ "$major" -eq 6 ] && [ "$minor" -ge 14 ] && [ "$minor" -le 17 ]
}

install_uart_dma_fix() {
    uart_dma_deadlock_kernel || return 0
    [ -f "$UART_DMA_FIX_SRC" ] || return 0

    local action="installed"
    if [ -f "$UART_DMA_FIX_DEST" ]; then
        cmp -s "$UART_DMA_FIX_SRC" "$UART_DMA_FIX_DEST" && return 0
        if ! grep -aqF "$UART_DMA_FIX_MARKER" "$UART_DMA_FIX_DEST"; then
            printf '%b\n' "${Y}${UART_DMA_FIX_DEST} belongs to something else; UART DMA fix for MCU disconnects (#444) not installed.${NC}"
            return 0
        fi
        action="updated"
    elif [ ! -e "$UART_DMA_FIX_NODE/dma-names" ]; then
        # DMA is already off on this UART (e.g. a patched DTB), nothing to fix
        return 0
    fi

    if ! grep -aqF "fixup.scr" "$UART_DMA_FIX_BOOT_SCR" 2>/dev/null; then
        printf '%b\n' "${Y}${UART_DMA_FIX_BOOT_SCR} does not load a fixup script; UART DMA fix for MCU disconnects (#444) not installed.${NC}"
        return 0
    fi

    if sudo cp "$UART_DMA_FIX_SRC" "$UART_DMA_FIX_DEST" && sync; then
        printf '%b\n' "${G}UART DMA fix for MCU disconnects (#444) ${action}. Reboot to apply.${NC}"
        sleep 2
    else
        printf '%b\n' "${R}Failed to install ${UART_DMA_FIX_DEST}.${NC}"
    fi
}

# USB-C toolhead power on GPIO82 (OpenNept4une#417).
TOOLHEAD_POWER_SRC_DIR="${HOME}/OpenNept4une/img-config/toolhead-power"
TOOLHEAD_POWER_SERVICE="opennept4une-toolhead-power.service"
TOOLHEAD_POWER_HELPER="/usr/local/sbin/opennept4une-toolhead-power"
TOOLHEAD_POWER_UNIT="/etc/systemd/system/${TOOLHEAD_POWER_SERVICE}"
TOOLHEAD_POWER_DROPIN="/etc/systemd/system/klipper.service.d/opennept4une-toolhead-power.conf"

# The service follows the model flag. GPIO82 is only ever driven on printers set to the
# USB-C printhead: what the pin does on the other boards is unknown.
sync_toolhead_power() {
    if [[ "$MODEL_FROM_FLAG" =~ -tusbc$ ]]; then
        install_toolhead_power
    else
        remove_toolhead_power
    fi
}

install_toolhead_power() {
    local src dest mode changed=false
    while read -r src dest mode; do
        if [ ! -f "$src" ]; then
            printf '%b\n' "${R}Missing ${src}; USB-C toolhead power not installed.${NC}"
            return 1
        fi
        cmp -s "$src" "$dest" && continue
        if ! sudo install -D -m "$mode" "$src" "$dest"; then
            printf '%b\n' "${R}Failed to install ${dest}.${NC}"
            return 1
        fi
        changed=true
    done <<EOF
${TOOLHEAD_POWER_SRC_DIR}/opennept4une-toolhead-power.sh ${TOOLHEAD_POWER_HELPER} 0755
${TOOLHEAD_POWER_SRC_DIR}/opennept4une-toolhead-power.service ${TOOLHEAD_POWER_UNIT} 0644
${TOOLHEAD_POWER_SRC_DIR}/klipper-toolhead-power.conf ${TOOLHEAD_POWER_DROPIN} 0644
EOF

    $changed && sudo systemctl daemon-reload >/dev/null 2>&1
    systemctl is-enabled --quiet "$TOOLHEAD_POWER_SERVICE" 2>/dev/null || \
        sudo systemctl enable "$TOOLHEAD_POWER_SERVICE" >/dev/null 2>&1

    if ! $changed && systemctl is-active --quiet "$TOOLHEAD_POWER_SERVICE"; then
        return 0
    fi
    printf '%s\n' "Switching on USB-C toolhead power (GPIO82), waiting for the toolhead..."
    # "on" is idempotent, so restarting an active service never drops the toolhead power
    if ! sudo systemctl restart "$TOOLHEAD_POWER_SERVICE"; then
        printf '%b\n' "${R}USB-C toolhead power failed to start. See: journalctl -u ${TOOLHEAD_POWER_SERVICE}${NC}"
        return 1
    fi
    if usb_c_toolhead_detected; then
        printf '%b\n' "${G}USB-C toolhead power is on and the toolhead is connected. Restart Klipper if it reports mcu 'THR' unable to connect.${NC}"
    else
        printf '%b\n' "${Y}USB-C toolhead power is on, but no toolhead has appeared yet. Check: sudo opennept4une-toolhead-power status${NC}"
    fi
    sleep 1
}

remove_toolhead_power() {
    [ -e "$TOOLHEAD_POWER_UNIT" ] || [ -e "$TOOLHEAD_POWER_DROPIN" ] || [ -e "$TOOLHEAD_POWER_HELPER" ] || return 0
    sudo systemctl disable --now "$TOOLHEAD_POWER_SERVICE" >/dev/null 2>&1
    sudo rm -f "$TOOLHEAD_POWER_UNIT" "$TOOLHEAD_POWER_DROPIN" "$TOOLHEAD_POWER_HELPER"
    sudo rmdir --ignore-fail-on-non-empty "$(dirname "$TOOLHEAD_POWER_DROPIN")" 2>/dev/null
    sudo systemctl daemon-reload >/dev/null 2>&1
    # Stopping the service leaves GPIO82 as it is; it resets at the next boot
    printf '%b\n' "${Y}Printhead is set to ribbon; removed the USB-C toolhead power service.${NC}"
}
