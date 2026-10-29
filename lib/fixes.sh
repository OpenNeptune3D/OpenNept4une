# shellcheck shell=bash
# One-off system fixes applied on every run.
# Sourced by OpenNept4une.sh; defines functions only.

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
}
