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
    # Values passed on the command line take precedence over the stored flag.
    local cli_model="$model_key" cli_current="$motor_current"
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

    if [[ -n "$cli_model" && "$cli_model" != "$model_key" ]]; then
        printf '%b\n' "${Y}Using --printer_model=${cli_model} (stored flag says ${model_key}).${NC}"
        model_key="$cli_model"
    fi
    if [[ "$model_key" == "n4" || "$model_key" == "n4pro" ]]; then
        [[ -n "$cli_current" ]] && motor_current="$cli_current"
    else
        motor_current=""
    fi
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

# The Z probe is kept on its own "probe=<name>" line in $FLAG_FILE, apart from
# the model line, so it does not interfere with the "-t..." toolhead suffix.
read_probe_flag() {
    grep -m1 '^probe=' "$FLAG_FILE" 2>/dev/null | cut -d= -f2
}

update_probe_flag() {
    local new_probe="$1"
    [ "$(read_probe_flag)" = "$new_probe" ] && return 0
    sudo sed -i '/^probe=/d' "$FLAG_FILE"
    echo "probe=${new_probe}" | sudo tee -a "$FLAG_FILE" > /dev/null
    sync
}

# Sets probe_variant: --probe on the command line (saved), else the saved
# value, else ask once (saved). Defaults to the stock probe.
select_probe_variant() {
    local stored
    stored=$(read_probe_flag)
    if [ -n "$probe_variant" ]; then
        update_probe_flag "$probe_variant"
        return 0
    fi
    case "$stored" in
        stock|cartographer|beacon|eddy) probe_variant="$stored"; return 0 ;;
    esac

    if [[ "$auto_yes" == "true" ]]; then
        probe_variant="stock"
        local f
        for f in cartographer beacon eddy; do
            if [ -f "${HOME}/printer_data/config/${f}.cfg" ]; then
                printf '%b\n' "${Y}Found ${f}.cfg but no probe is saved; using the stock probe. Pass --probe=${f} to use it.${NC}"
            fi
        done
    else
        printf '\n%s\n' "Which Z probe does this machine have?"
        printf '%s\n' "  1) Stock probe (default)"
        printf '%s\n' "  2) Cartographer"
        printf '%s\n' "  3) Beacon"
        printf '%s\n' "  4) BTT Eddy (USB)"
        read -r -p "$(printf '%b' "${M}Enter your choice [1-4, default 1] ${NC}: ")" PROBE_CHOICE
        case "$PROBE_CHOICE" in
            2) probe_variant="cartographer" ;;
            3) probe_variant="beacon" ;;
            4) probe_variant="eddy" ;;
            *) probe_variant="stock" ;;
        esac
    fi
    update_probe_flag "$probe_variant"
}

# Cartographer V3 and V4 put the onboard accelerometer on different pins, and
# the wrong one bootloops the probe, so ask. Sets probe_accel to v3, v4 or
# none; left empty (headless, no --probe_accel) generate_conf.py decides from
# the probe's USB name.
select_cartographer_accel() {
    [ -n "$probe_accel" ] && return 0
    [[ "$auto_yes" == "true" ]] && return 0

    local detected="" default_choice="3" dev
    dev=$(compgen -G "/dev/serial/by-id/usb-Cartographer_*" | head -n 1)
    case "${dev,,}" in
        *stm32g431*|*stm32g474*) detected="V4"; default_choice="1" ;;
        *stm32f042*) detected="V3"; default_choice="2" ;;
    esac

    printf '\n%s\n' "Which Cartographer is this? (sets up its built-in accelerometer)"
    [ -n "$detected" ] && printf '%s\n' "  The connected probe reports itself as ${detected}."
    printf '%s\n' "  1) Cartographer V4"
    printf '%s\n' "  2) Cartographer V3"
    printf '%s\n' "  3) Don't set up the probe's accelerometer"
    read -r -p "$(printf '%b' "${M}Enter your choice [1-3, default ${default_choice}] ${NC}: ")" ACCEL_CHOICE
    case "${ACCEL_CHOICE:-$default_choice}" in
        1) probe_accel="v4" ;;
        2) probe_accel="v3" ;;
        *) probe_accel="none" ;;
    esac
}

# A scanning probe's settings live in ~/printer_data/config/<probe>.cfg, which
# printer.cfg includes. Create it from the template once if it is missing; an
# existing file is never touched.
ensure_probe_cfg() {
    [ "$probe_variant" = "stock" ] && return 0
    local probe_cfg="${HOME}/printer_data/config/${probe_variant}.cfg"
    [ -f "$probe_cfg" ] && return 0

    printf '\n%b\n' "${Y}${probe_cfg} does not exist yet; creating it from the OpenNept4une template.${NC}"
    if [ -z "$probe_offset" ]; then
        if [[ "$auto_yes" == "true" ]]; then
            printf '%b\n' "${R}Pass --probe_offset=X,Y (probe offset from the nozzle in mm) to create it non-interactively.${NC}"
            return 1
        fi
        printf '%s\n' "Enter the probe's offset from the nozzle in mm, as X,Y (depends on your mount, e.g. 0,22)."
        read -r -p "$(printf '%b' "${M}Probe offset X,Y ${NC}: ")" probe_offset
    fi
    local extra_args=()
    [ -n "$probe_serial" ] && extra_args+=(--probe-serial "$probe_serial")
    if [ "$probe_variant" = "cartographer" ]; then
        select_cartographer_accel
        [ -n "$probe_accel" ] && extra_args+=(--probe-accel "$probe_accel")
    fi
    if ! python3 "${HOME}/OpenNept4une/printer-confs/generate_conf.py" "${model_key}" \
            --probe "${probe_variant}" --seed-probe-cfg --probe-offset "${probe_offset}" \
            --toolhead "${toolhead_variant}" "${extra_args[@]}"; then
        printf '%b\n' "${R}Could not create ${probe_cfg}.${NC}"
        return 1
    fi
    printf '%b\n' "${Y}Review ${probe_cfg}, then run Calibrate_Probe_Z_Offset after Klipper restarts.${NC}"
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
            read -r -p "$(printf '%b' "${M}Enter your choice [1/2, default 1] ${NC}: ")" TOOLHEAD_CHOICE
            if [[ "$TOOLHEAD_CHOICE" == "2" ]]; then
                toolhead_variant="usb-c"
            else
                toolhead_variant="ribbon"
            fi
        fi
        update_toolhead_flag "$toolhead_variant"
    fi

    # The USB-C toolhead only appears on USB once GPIO82 powers it, so it cannot be
    # required before the choice is saved. Power it now, then look for it.
    sync_toolhead_power
    if [ "$toolhead_variant" = "usb-c" ] && ! usb_c_toolhead_detected; then
        printf '%b\n' "${R}No USB-C Klipper toolhead found (expected /dev/serial/by-id/usb-Klipper_stm32f103xe_*).${NC}"
        printf '%s\n' "Toolhead power: $(sudo "$TOOLHEAD_POWER_HELPER" status 2>&1 | tr '\n' ' ')"
        printf '%s\n' "Check the USB-C cable, then run Install/Update printer.cfg again. If this machine has the ribbon-cable printhead, run: opennept4une --toolhead=ribbon install_printer_cfg"
        return 1
    fi

    select_probe_variant
    if ! ensure_probe_cfg; then
        return 1
    fi
    # Lets generate_conf.py fill in or correct the probe's serial in <probe>.cfg.
    local probe_serial_args=()
    [ -n "$probe_serial" ] && probe_serial_args=(--probe-serial "$probe_serial")

    # Build config based on user selection
    if [[ $model_key == "n4" || $model_key == "n4pro" ]]; then
        if ! python3 "${HOME}/OpenNept4une/printer-confs/generate_conf.py" "${model_key}" "${motor_current}" --toolhead "${toolhead_variant}" --probe "${probe_variant}" "${probe_serial_args[@]}"; then
            printf '%b\n' "${R}Failed to generate printer configuration.${NC}"
            return 1
        fi
        sync
    else
        if ! python3 "${HOME}/OpenNept4une/printer-confs/generate_conf.py" "${model_key}" --toolhead "${toolhead_variant}" --probe "${probe_variant}" "${probe_serial_args[@]}"; then
            printf '%b\n' "${R}Failed to generate printer configuration.${NC}"
            return 1
        fi
        sync
    fi
    sleep 1

    mkdir -p "$PRINTER_CFG_DEST" "$DATABASE_DEST"
    touch "${HOME}/printer_data/config/user_settings.cfg"

    # printer.cfg is rebuilt from the templates, so hand edits in it are lost.
    # List them first (exit status 2 = some found), so they can be moved to
    # user_settings.cfg or the probe's include file.
    if [[ -f "$PRINTER_CFG_FILE" ]]; then
        local edit_status=0
        printf '\n'
        python3 "${HOME}/OpenNept4une/printer-confs/generate_conf.py" --check-edits \
            "$PRINTER_CFG_FILE" "$PRINTER_CFG_SOURCE" --probe "${probe_variant}" || edit_status=$?
        if [[ $edit_status -eq 2 ]]; then
            printf '%b\n' "${Y}The current printer.cfg is kept as a backup-printer.cfg.bak* file either way.${NC}"
            if [[ "$auto_yes" != "true" ]]; then
                read -r -p "$(printf '%b' "${M}Continue with the update now? (y/n) ${NC}: ")" EDITS_CHOICE
                if [[ ! "$EDITS_CHOICE" =~ ^[Yy]$ ]]; then
                    printf '\n%s\n' "${Y}Update stopped. Move the settings above, then run it again.${NC}"
                    return 0
                fi
            fi
        elif [[ $edit_status -ne 0 ]]; then
            printf '%b\n' "${Y}Could not check printer.cfg for hand edits; continuing.${NC}"
        fi
    fi

    local DIFF_CHOICE="n"
    if [[ "$auto_yes" != "true" ]]; then
        printf '%s\n\n' "${G}Would you like to compare/diff your current printer.cfg with the latest? (y/n).${NC}"
        read -r -p "$(printf '%b' "${M}Enter your choice ${NC}: ")" DIFF_CHOICE
    fi

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
            # Baseline for the next update's hand-edit check (generate_conf.py --check-edits).
            cp "$PRINTER_CFG_SOURCE" "${HOME}/OpenNept4une/printer-confs/last_applied.cfg" 2>/dev/null || true
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
