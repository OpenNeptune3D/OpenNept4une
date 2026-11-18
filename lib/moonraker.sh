# shellcheck shell=bash
# Moonraker update_manager entries for OpenNept4une and the display repos.
# Sourced by OpenNept4une.sh; defines functions only.

moonraker_update_manager() {
    local update_selection="$1"
    local config_file="$HOME/printer_data/config/moonraker.conf"
    local new_lines=""

    if [ "$update_selection" = "OpenNept4une" ]; then
        local current_ON_branch
        current_ON_branch=$(git -C "$OPENNEPT4UNE_DIR" symbolic-ref --short HEAD 2>/dev/null)
        new_lines=$(cat <<EOF
[update_manager $update_selection]
type: git_repo
primary_branch: $current_ON_branch
path: $OPENNEPT4UNE_DIR
is_system_service: False
origin: $OPENNEPT4UNE_REPO
EOF
)

    elif [ "$update_selection" = "display" ]; then
        local current_display_branch
        current_display_branch=$(git -C "$DISPLAY_CONNECTOR_DIR" symbolic-ref --short HEAD 2>/dev/null)
        new_lines=$(cat <<EOF
[update_manager $update_selection]
type: git_repo
primary_branch: $current_display_branch
path: $DISPLAY_CONNECTOR_DIR
virtualenv: $DISPLAY_CONNECTOR_DIR/venv
requirements: requirements.txt
origin: $DISPLAY_CONNECTOR_REPO
managed_services: display
EOF
)

    elif [ "$update_selection" = "display_firmware" ]; then
        local current_firmware_branch
        current_firmware_branch=$(git -C "$DISPLAY_FIRMWARE_DIR" symbolic-ref --short HEAD 2>/dev/null)
        new_lines=$(cat <<EOF
[update_manager $update_selection]
type: git_repo
primary_branch: $current_firmware_branch
path: $DISPLAY_FIRMWARE_DIR
is_system_service: False
virtualenv: $DISPLAY_FIRMWARE_DIR/venv
requirements: requirements.txt
origin: $DISPLAY_FIRMWARE_REPO
EOF
)

    else
        printf '%b\n' "${R}Invalid argument. Please specify either 'OpenNept4une', 'display', or 'display_firmware'.${NC}"
        return 1
    fi
    
    # Update or append block
    if grep -qF "[update_manager $update_selection]" "$config_file" 2>/dev/null; then
        # Use awk for safer in-place editing
        local temp_file
        temp_file=$(mktemp)
        awk -v section="[update_manager $update_selection]" -v new_content="$new_lines" '
        BEGIN { in_section=0; printed=0 }
        $0 == section { in_section=1; print new_content; printed=1; next }
        in_section && /^\[/ { in_section=0 }
        !in_section { print }
        ' "$config_file" > "$temp_file"
        
        if [ -s "$temp_file" ]; then
            mv "$temp_file" "$config_file"
            sync
        else
            rm -f "$temp_file"
        fi
    else
        if [ -s "$config_file" ] && [ "$(tail -c1 "$config_file" 2>/dev/null)" != $'\n' ]; then
            echo >> "$config_file"
        fi
        printf "\n%s\n" "$new_lines" >> "$config_file"
    fi
}
