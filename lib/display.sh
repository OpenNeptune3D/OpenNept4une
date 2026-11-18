# shellcheck shell=bash
# Touch-screen display service and display firmware install.
# Sourced by OpenNept4une.sh; defines functions only.

display_firmware() {
    clear_screen
    printf '%b\n' "${C}${OPENNEPT4UNE_ART}${NC}"
    printf '\n'

    if [ -z "$current_branch" ]; then
        printf '%s\n' "Error: current_branch is not set. Exiting."
        exit 1
    fi

    if [ ! -d "$DISPLAY_FIRMWARE_DIR" ]; then
        if git clone -b "$current_branch" "${DISPLAY_FIRMWARE_REPO}" "${DISPLAY_FIRMWARE_DIR}"; then
            printf '%b\n' "${G}Initialized repository for Display Firmware Scripts.${NC}"
        else
            printf '%b\n' "${R}Failed to clone Display Firmware repository.${NC}"
            return 1
        fi
    fi

    install_feature "Flash/Update Display Firmware (Alpha)" "$UPDATED_DISPLAY_FIRMWARE_INSTALLER" "Do you want to run Flash/Update Display Firmware (Alpha)?"
}

install_screen_service() {
    install_feature "Touch-Screen Display Service" run_install_screen_service_with_setup "Do you want to install the Touch-Screen Display Service?"
}

run_install_screen_service_with_setup() {
    # Reset an existing checkout to its remote branch instead of re-cloning; only a
    # broken or detached checkout is removed so initialize_display_connector clones fresh.
    local display_branch
    display_branch=$(git -C "$DISPLAY_CONNECTOR_DIR" branch --show-current 2>/dev/null)
    if [ -n "$display_branch" ]; then
        if ! git -C "$DISPLAY_CONNECTOR_DIR" fetch origin "$display_branch" --quiet; then
            printf '%b\n' "${R}Failed to fetch Display Connector updates; leaving $DISPLAY_CONNECTOR_DIR untouched.${NC}"
            return 1
        fi
        if ! git -C "$DISPLAY_CONNECTOR_DIR" reset --hard "origin/$display_branch" --quiet || \
           ! git -C "$DISPLAY_CONNECTOR_DIR" clean -fd --quiet; then
            printf '%b\n' "${R}Failed to reset Display Connector to origin/$display_branch.${NC}"
            return 1
        fi
        printf '%b\n' "${G}Reset Display Connector to origin/$display_branch.${NC}"
    else
        rm -rf "$DISPLAY_CONNECTOR_DIR"
    fi

    if initialize_display_connector && [ -f "$DISPLAY_SERVICE_INSTALLER" ]; then
        bash "$DISPLAY_SERVICE_INSTALLER"
    else
        printf '%b\n' "${R}Failed to initialize display connector or installer not found.${NC}"
        return 1
    fi
}

initialize_display_connector() {
    if [ ! -d "${HOME}/display_connector" ]; then
        # Follow OpenNept4une's branch, falling back to main when display_connector doesn't have it.
        local clone_branch="${current_branch:-main}"
        if ! git ls-remote --exit-code --heads "$DISPLAY_CONNECTOR_REPO" "$clone_branch" >/dev/null 2>&1; then
            printf '%b\n' "${Y}Display Connector has no '$clone_branch' branch, using 'main'.${NC}"
            clone_branch="main"
        fi
        if git clone -b "$clone_branch" "${DISPLAY_CONNECTOR_REPO}" "${DISPLAY_CONNECTOR_DIR}"; then
            printf '%b\n' "${G}Initialized repository for Touch-Screen Display Service.${NC}"
        else
            printf '%b\n' "${R}Failed to clone Display Connector repository.${NC}"
            return 1
        fi
    fi
    moonraker_update_manager "display"
}
