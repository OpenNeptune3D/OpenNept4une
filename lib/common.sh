# shellcheck shell=bash
# Shared helpers: screen clearing, the install prompt wrapper and branch detection.
# Sourced by OpenNept4une.sh; defines functions only.

clear_screen() {
    # Clear the screen and move the cursor to the top left
    clear
    tput cup 0 0
}

set_current_branch() {
    current_branch=$(git -C "$OPENNEPT4UNE_DIR" symbolic-ref --short HEAD 2>/dev/null)
}

install_feature() {
    local feature_name="$1"
    local action="$2"  # This can be a script path or direct commands
    local prompt_message="$3"

    clear_screen
    printf '%b\n' "${C}${OPENNEPT4UNE_ART}${NC}"
    printf '%s\n' "=========================================================="
    printf '%s\n' "$feature_name ${M}Installation${NC}"
    printf '%s\n' "=========================================================="

    local user_input=""
    if [ "$auto_yes" != "true" ]; then
        printf '%b ' "${M}$prompt_message (Y/n)${NC}: "
        read -r user_input
        printf '\n'
    fi

    if [[ $user_input =~ ^[Yy]$|^$ ]] || [ "$auto_yes" = "true" ]; then
        printf '%s\n\n' "Running $feature_name Installer..."
        
        # Check if action is a file (script) or a command
        if [[ -f "$action" ]]; then
            if bash "$action"; then
                printf '%b\n' "${G}$feature_name Installer ran successfully.${NC}"
                sleep 2
            else
                printf '%b\n' "${R}$feature_name Installer encountered an error.${NC}"
                sleep 1
            fi
        elif [[ -n "$action" ]]; then
            if eval "$action"; then
                printf '%b\n' "${G}$feature_name Installer ran successfully.${NC}"
                sleep 2
            else
                printf '%b\n' "${R}$feature_name Installer encountered an error.${NC}"
                sleep 1
            fi
        else
            printf '%b\n' "${R}Error: Action for $feature_name not found or not specified.${NC}"
            sleep 1
        fi
    else
        printf '%b\n' "${Y}Installation skipped.${NC}"
        sleep 1
    fi

    printf '%s\n' "=========================================================="
}
