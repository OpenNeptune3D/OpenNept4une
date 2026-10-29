# shellcheck shell=bash
# Self-update of OpenNept4une and the display repos, and main/dev branch switching.
# Sourced by OpenNept4une.sh; defines functions only.

update_repo() {
    clear_screen
    printf '%b\n' "${C}${OPENNEPT4UNE_ART}${NC}"
    printf '\n'
    printf '%s\n' "=========================================================="
    printf '%b\n' "${M}Checking for updates...${NC}"
    printf '%s\n\n' "=========================================================="

    process_repo_update "$OPENNEPT4UNE_DIR" "OpenNept4une"
    moonraker_update_manager "OpenNept4une"

    if [ -d "${HOME}/OpenNept4une/display/venv" ]; then
        printf '%b' "${Y}The Touch-Screen Display Service was moved to a different directory. Do you want to run the automatic migration?${NC} (Y/n): "
        read -r user_input
        if [[ $user_input =~ ^[Yy]$|^$ ]]; then
            if initialize_display_connector && bash "$DISPLAY_SERVICE_INSTALLER"; then
                rm -rf "${HOME}/OpenNept4une/display"
            fi
        else
            printf '%b\n' "${Y}Skipping migration. ${R}The Display Service will not work until the migration is completed.${NC}"
            sleep 2
        fi
    else
        if [ -d "$DISPLAY_CONNECTOR_DIR" ]; then
            local display_before display_after
            display_before=$(git -C "$DISPLAY_CONNECTOR_DIR" rev-parse HEAD 2>/dev/null)
            process_repo_update "$DISPLAY_CONNECTOR_DIR" "Display Connector"
            moonraker_update_manager "display"
            display_after=$(git -C "$DISPLAY_CONNECTOR_DIR" rev-parse HEAD 2>/dev/null)
            if [ -n "$display_before" ] && [ "$display_before" != "$display_after" ]; then
                apply_display_connector_update "$display_before" "$display_after"
            fi
        fi
    fi

    if [ -d "${HOME}/display_firmware/venv" ]; then
        process_repo_update "$DISPLAY_FIRMWARE_DIR" "Display Firmware"
        moonraker_update_manager "display_firmware"
    else
        printf '%b\n' "${Y}Skipping Display Firmware update: $DISPLAY_FIRMWARE_DIR does not exist.${NC}"
    fi

    printf '%s\n' "=========================================================="
}

# Moonraker reinstalls requirements and restarts the service when it updates the
# repo; do the same after a pull made by this script.
apply_display_connector_update() {
    local before="$1"
    local after="$2"
    local pip_bin="$DISPLAY_CONNECTOR_DIR/venv/bin/pip"

    if ! git -C "$DISPLAY_CONNECTOR_DIR" diff --quiet "$before" "$after" -- requirements.txt && [ -x "$pip_bin" ]; then
        printf '%b\n' "${Y}Display Connector requirements changed, updating virtualenv...${NC}"
        if ! "$pip_bin" install --prefer-binary -r "$DISPLAY_CONNECTOR_DIR/requirements.txt"; then
            printf '%b\n' "${R}Failed to update Display Connector requirements. Re-run the Touch-Screen Service install if the display stops working.${NC}"
            sleep 2
        fi
    fi

    if systemctl is-enabled --quiet display.service 2>/dev/null; then
        printf '%s\n' "Restarting display.service..."
        sudo systemctl restart display.service || printf '%b\n' "${R}Failed to restart display.service.${NC}"
    fi
}

process_repo_update() {
    local repo_dir="$1"
    local name="$2"
    local update_branch
    local REPLY=""

    if [ ! -d "$repo_dir" ]; then
        printf '%b\n' "${R}Repository directory not found at $repo_dir!${NC}"
        sleep 5
        return 1
    fi

    update_branch=$(git -C "$repo_dir" branch --show-current 2>/dev/null)

    if [ -z "$update_branch" ]; then
        printf '%b\n' "${R}Could not determine the current branch for $repo_dir!${NC}"
        sleep 5
        return 1
    fi

    # Fetch updates
    if ! git -C "$repo_dir" fetch origin "$update_branch" --quiet; then
        printf '%b\n' "${R}Failed to fetch updates for ${name}.${NC}"
        sleep 5
        return 1
    fi

    LOCAL=$(git -C "$repo_dir" rev-parse '@')
    REMOTE=$(git -C "$repo_dir" rev-parse '@{u}')

    if [ "$LOCAL" != "$REMOTE" ]; then
        printf '%b\n' "${Y}Updates are available for ${name}.${NC}"
        if [ "$auto_yes" != "true" ]; then
            printf '%s' "Would you like to update ${G}● ${name}?${NC} (y/n): "
            read -r REPLY
        else
            REPLY="y"
        fi

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            printf '%s\n' "Updating..."
            # Attempt to pull and capture any errors
            if ! UPDATE_OUTPUT=$(git -C "$repo_dir" pull origin "$update_branch" 2>&1); then
                # Check for the specific divergent branches error message
                if echo "$UPDATE_OUTPUT" | grep -q "divergent branches"; then
                    printf '%b\n' "${R}Divergent branches detected, performing a hard reset to origin/${update_branch}...${NC}"
                    sleep 1
                    if ! git -C "$repo_dir" reset --hard "origin/${update_branch}"; then
                        printf '%b\n' "${R}Failed to hard reset ${name}.${NC}"
                        sleep 1
                        return 1
                    fi
                    if ! git -C "$repo_dir" clean -fd; then
                        printf '%b\n' "${R}Failed to clean ${name}.${NC}"
                        sleep 1
                        return 1
                    fi
                else
                    printf '%b\n' "${R}Failed to update ${name}: $UPDATE_OUTPUT${NC}"
                    sleep 1
                    return 1
                fi
            fi

            printf '%b\n' "${name} ${G}Updated successfully.${NC}"
            sleep 1
        else
            printf '%b\n' "${Y}Update skipped.${NC}"
            sleep 1
        fi
    else
        printf '%b\n\n' "${G}●${NC} ${name} ${G}is already up-to-date.${NC}"
        sleep 1
    fi

    printf '%s\n\n' "=========================================================="
}

toggle_branch() {
    clear_screen
    printf '%b\n' "${C}${OPENNEPT4UNE_ART}${NC}"
    printf '\n'

    switch_branch() {
        local branch_name="$1"
        local repo_dir="$2"
        if [ -d "$repo_dir" ]; then
            git -C "$repo_dir" reset --hard >/dev/null 2>&1
            git -C "$repo_dir" clean -fd >/dev/null 2>&1
            if git -C "$repo_dir" checkout "$branch_name" >/dev/null 2>&1; then
                printf '%b\n' "${G}Switched $repo_dir to $branch_name.${NC}"
                return 0
            fi
        fi
        return 1
    }

    if [ -d "$OPENNEPT4UNE_DIR" ]; then
        if [ -n "$current_branch" ]; then
            printf '%s' "You are currently on the ${G}'$current_branch'${NC} branch. "
            local target_branch
            if [ "$current_branch" = "main" ]; then
                target_branch="dev"
            else
                target_branch="main"
            fi
            local dirty
            dirty=$(git -C "$OPENNEPT4UNE_DIR" status --porcelain 2>/dev/null | wc -l)
            if [ "$dirty" -gt 0 ]; then
                printf '\n%b\n' "${R}Warning: ${dirty} locally modified/untracked file(s) in $OPENNEPT4UNE_DIR will be discarded (git reset --hard + clean).${NC}"
            fi
            printf '%b ' "${M}Would you like to switch to the '$target_branch' branch?${NC} (y/n): "
            read -r user_response
            if [[ $user_response =~ ^[Yy]$ ]]; then
                # Switch OpenNept4une repo (always present)
                if switch_branch "$target_branch" "$OPENNEPT4UNE_DIR"; then
                    moonraker_update_manager "OpenNept4une"
                fi
                
                # Switch display_connector repo only if it exists
                if switch_branch "$target_branch" "$DISPLAY_CONNECTOR_DIR"; then
                    moonraker_update_manager "display"
                elif [ -d "$DISPLAY_CONNECTOR_DIR" ]; then
                    printf '%b\n' "${R}Could not switch $DISPLAY_CONNECTOR_DIR to $target_branch; it stays on $(git -C "$DISPLAY_CONNECTOR_DIR" branch --show-current 2>/dev/null).${NC}"
                    sleep 2
                fi
                
                # Switch display_firmware repo only if it exists and has venv (indicating it's installed)
                if [ -d "${DISPLAY_FIRMWARE_DIR}/venv" ] && switch_branch "$target_branch" "$DISPLAY_FIRMWARE_DIR"; then
                    moonraker_update_manager "display_firmware"
                fi
                
                printf '%b\n' "${G}Branch switch operation completed.${NC}"
                sync
                sudo service moonraker restart
                exec "$SCRIPT"
                exit 0
            else
                printf '%b\n' "${Y}Branch switch operation aborted.${NC}"
            fi
        else
            printf '%b\n' "${R}Could not determine the current branch for $OPENNEPT4UNE_DIR.${NC}"
        fi
    else
        printf '%b\n' "${R}$OPENNEPT4UNE_DIR does not exist or is not accessible.${NC}"
    fi
}
