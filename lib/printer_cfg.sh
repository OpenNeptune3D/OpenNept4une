# shellcheck shell=bash
# printer.cfg generation: model, motor current and toolhead selection.
# Sourced by OpenNept4une.sh; defines functions only.

check_and_set_printer_model() {
    if [ -z "$MODEL_FROM_FLAG" ]; then
        printf '%s\n' "Model Flag is empty. Running Set Model script..."
        if [ -f "${HOME}/OpenNept4une/img-config/set-printer-model.sh" ]; then
            export model_key motor_current pcb_version auto_yes toolhead_variant
            "${HOME}/OpenNept4une/img-config/set-printer-model.sh"
        else
            printf '%b\n' "${R}Error: set-printer-model.sh not found.${NC}"
            return 1
        fi
        MODEL_FROM_FLAG=$(grep -E '^N4|^n4' "$FLAG_FILE" 2>/dev/null)
        if [ -z "$MODEL_FROM_FLAG" ]; then
            printf '%s\n' "Failed to set Model Flag. Exiting."
            return 1
        else
            printf '%s\n' "Model Flag set successfully."
        fi
        return 0
    else
        printf '%s\n' "Model Detected: $MODEL_FROM_FLAG"
        return 0
    fi
}

# Check whether a USB-C Klipper toolhead MCU is currently connected
usb_c_toolhead_detected() {
    compgen -G "/dev/serial/by-id/usb-Klipper_stm32f103xe_*" > /dev/null
}

extract_model_and_motor() {
    model_key=$(echo "$MODEL_FROM_FLAG" | cut -d'-' -f1 | tr '[:upper:]' '[:lower:]')
    pcb_version=$(echo "$MODEL_FROM_FLAG" | sed -E 's/.*-v([0-9.]+).*/\1/')

    # motor_current is only encoded in the flag for n4/n4pro (e.g.
    # "N4pro-1.2A-v1.1"); n4plus/n4max flags have no "<value>A" segment, so
    # leave it empty rather than matching the whole flag string.
    motor_current=""
    if [[ "$model_key" == "n4" || "$model_key" == "n4pro" ]]; then
        motor_current=$(echo "$MODEL_FROM_FLAG" | sed -E 's/^[^-]*-([0-9.]+)A.*/\1/')
    fi

    # Toolhead variant is stored as a "-tribbon" / "-tusbc" suffix on the
    # flag line. Older flags without this suffix are treated as "ribbon".
    flag_toolhead=$(echo "$MODEL_FROM_FLAG" | sed -nE 's/.*-t(ribbon|usbc)$/\1/p')
    case "$flag_toolhead" in
        usbc) flag_toolhead="usb-c" ;;
        ribbon|"") flag_toolhead="ribbon" ;;
    esac
}

# Update (or add) the "-tribbon"/"-tusbc" suffix on the persisted model flag
# line in $FLAG_FILE, so headless reflashes remember the toolhead variant.
update_toolhead_flag() {
    local new_toolhead="$1" # "ribbon" or "usb-c"
    local suffix="ribbon"
    [ "$new_toolhead" = "usb-c" ] && suffix="usbc"

    local new_flag
    if echo "$MODEL_FROM_FLAG" | grep -qE -- '-t(ribbon|usbc)$'; then
        new_flag=$(echo "$MODEL_FROM_FLAG" | sed -E "s/-t(ribbon|usbc)\$/-t${suffix}/")
    else
        new_flag="${MODEL_FROM_FLAG}-t${suffix}"
    fi

    if [ "$new_flag" != "$MODEL_FROM_FLAG" ]; then
        sudo sed -i '/^n4/I d' "$FLAG_FILE"
        echo "$new_flag" | sudo tee -a "$FLAG_FILE" > /dev/null
        sync
        MODEL_FROM_FLAG="$new_flag"
    fi
}

install_printer_cfg() {
    clear_screen
    printf '%b\n' "${C}${OPENNEPT4UNE_ART}${NC}"
    printf '\n'

    if ! check_and_set_printer_model; then
        return 1
    fi
    sleep 1

    extract_model_and_motor

    PRINTER_CFG_DEST="${HOME}/printer_data/config"
    DATABASE_DEST="${HOME}/printer_data/database"
    PRINTER_CFG_FILE="$PRINTER_CFG_DEST/printer.cfg"
    PRINTER_CFG_SOURCE="${HOME}/OpenNept4une/printer-confs/output.cfg"

    if [ -n "$toolhead_variant" ]; then
        # --toolhead was passed on the command line: use it and persist it.
        if [ "$toolhead_variant" = "usb-c" ] && ! usb_c_toolhead_detected; then
            printf '%b\n' "${R}ERROR: --toolhead usb-c specified but no USB-C Klipper toolhead detected (expected /dev/serial/by-id/usb-Klipper_stm32f103xe_*).${NC}"
            return 1
        fi
        update_toolhead_flag "$toolhead_variant"
    elif [ -n "$flag_toolhead" ] && echo "$MODEL_FROM_FLAG" | grep -qE -- '-t(ribbon|usbc)$'; then
        # Toolhead variant already recorded in the model flag from a
        # previous run (or initial setup) - reuse it without prompting.
        toolhead_variant="$flag_toolhead"
    else
        # No CLI flag and nothing recorded yet (e.g. flag set before this
        # feature existed): ask once and persist the answer.
        printf '\n%s\n' "Which printhead does this machine have?"
        printf '%s\n' "  1) Ribbon-cable printhead (default, original Neptune 4 toolhead)"
        printf '%s\n' "  2) USB-C Klipper printhead (separate toolhead MCU)"
        if [[ "$auto_yes" == "true" ]]; then
            toolhead_variant="ribbon"
        else
            while true; do
                read -r -p "$(printf '%b' "${M}Enter your choice [1/2, default 1] ${NC}: ")" TOOLHEAD_CHOICE
                if [[ "$TOOLHEAD_CHOICE" == "2" ]]; then
                    if usb_c_toolhead_detected; then
                        toolhead_variant="usb-c"
                        break
                    else
                        printf '%s\n' "No USB-C Klipper toolhead detected (expected /dev/serial/by-id/usb-Klipper_stm32f103xe_*). Connect the toolhead and try again, or choose option 1."
                    fi
                else
                    toolhead_variant="ribbon"
                    break
                fi
            done
        fi
        update_toolhead_flag "$toolhead_variant"
    fi

    # Build config based on user selection
    if [[ $model_key == "n4" || $model_key == "n4pro" ]]; then
        if ! python3 "${HOME}/OpenNept4une/printer-confs/generate_conf.py" "${model_key}" "${motor_current}" --toolhead "${toolhead_variant}"; then
            printf '%b\n' "${R}Failed to generate printer configuration.${NC}"
            return 1
        fi
        sync
    else
        if ! python3 "${HOME}/OpenNept4une/printer-confs/generate_conf.py" "${model_key}" --toolhead "${toolhead_variant}"; then
            printf '%b\n' "${R}Failed to generate printer configuration.${NC}"
            return 1
        fi
        sync
    fi
    sleep 1

    mkdir -p "$PRINTER_CFG_DEST" "$DATABASE_DEST"
    touch "${HOME}/printer_data/config/user_settings.cfg"

    printf '%s\n\n' "${G}Would you like to compare/diff your current printer.cfg with the latest? (y/n).${NC}"
    read -r -p "$(printf '%b' "${M}Enter your choice ${NC}: ")" DIFF_CHOICE

    if [[ "$DIFF_CHOICE" =~ ^[Yy]$ ]]; then
        clear_screen
        printf '\n'
        SPACES=$(printf '%*s' 32 '')
        printf '%b%s%b%s\n' "${C}" "Updated File:" "${NC}" "${SPACES}Current File:"
        printf '%b\n' "${C}==========================================================${NC}"

        DIFF_OUTPUT=$(diff -y --suppress-common-lines --width=58 \
            "${HOME}/OpenNept4une/printer-confs/output.cfg" \
            "${HOME}/printer_data/config/printer.cfg" 2>/dev/null
        )

        if [[ -z "$DIFF_OUTPUT" ]]; then
            printf '\n%s\n' "${G}There are no differences, Already up-to-date! ${NC}"
        else
            printf '%s\n' "$DIFF_OUTPUT"
        fi

        printf '\n%s\n\n' "${Y}Would you like to continue with the update? (y/n).${NC}"
        read -r -p "$(printf '%b' "${M}Enter your choice ${NC}: ")" CONTINUE_CHOICE

        if [[ "$CONTINUE_CHOICE" =~ ^[Yy]$ ]]; then
            printf '\n%s\n' "${G}Continuing with printer.cfg update.${NC}"
            sleep 1
        else
            printf '\n%s\n' "${Y}Exiting the update process.${NC}"
            sleep 1
            return 0
        fi
    else
        printf '\n%s\n' "${G}Continuing with printer.cfg update.${NC}"
        sleep 1
    fi

    apply_configuration
    sync
    printf '\n%s\n' "${Y}Restarting Klipper Service${NC}"
    sleep 2
    sudo service klipper restart
}

apply_configuration() {
    local backup_count=1
    local BACKUP_PRINTER_CFG_FILE="$PRINTER_CFG_DEST/backup-printer.cfg.bak$backup_count"
    
    while [[ -f "$BACKUP_PRINTER_CFG_FILE" ]]; do
        ((backup_count++))
        BACKUP_PRINTER_CFG_FILE="$PRINTER_CFG_DEST/backup-printer.cfg.bak$backup_count"
    done

    if [[ -f "$PRINTER_CFG_FILE" ]]; then
        if cp "$PRINTER_CFG_FILE" "$BACKUP_PRINTER_CFG_FILE"; then
            printf '\n%s\n\n' "${G}BACKUP of 'printer.cfg' created as '${BACKUP_PRINTER_CFG_FILE}'.${NC}"
            sleep 2
        else
            printf '%s\n' "${R}Error: Failed to create backup of 'printer.cfg'.${NC}"
        fi
        sleep 1
    fi

    if [[ -n "$PRINTER_CFG_SOURCE" && -f "$PRINTER_CFG_SOURCE" ]]; then
        if cp "$PRINTER_CFG_SOURCE" "$PRINTER_CFG_FILE"; then
            printf '%s\n\n' "${G}Printer configuration updated from '${PRINTER_CFG_SOURCE}'.${NC}"
            sleep 2
        else
            printf '%s\n' "${R}Error: Failed to update printer configuration from '${PRINTER_CFG_SOURCE}'.${NC}"
            sleep 1
        fi
    else
        printf '%s\n' "${R}Error: Invalid printer configuration file '${PRINTER_CFG_SOURCE}'.${NC}"
        return 1
    fi
}
