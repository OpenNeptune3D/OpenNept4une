# shellcheck shell=bash
# Install of KAMP/Moonraker/Fluidd/Mainsail and other config files.
# Sourced by OpenNept4une.sh; defines functions only.

install_configs() {
    clear_screen
    printf '%b\n' "${C}${OPENNEPT4UNE_ART}${NC}"
    printf '\n'

    # Menu label -> space-separated file list
    declare -A config_files=(
        ["All"]=""
        ["Fluidd web interface Conf"]="data.mdb"
        ["Moonraker Conf"]="moonraker.conf moonraker.asvc"
        ["KAMP Conf"]="KAMP_Settings.cfg"
        ["Mainsail web interface Conf"]="mainsail.cfg"
        ["Pico USB-C ADXL Conf"]="adxl.cfg"
        ["Klipper DEBUG Addon"]="klipper_debug.cfg"
    )

    # ----------------- Helpers -----------------

    dest_path_for() {
        local f="$1"
        case "$f" in
            data.mdb)          printf '%s\n' "${HOME}/printer_data/database/data.mdb" ;;
            moonraker.asvc)    printf '%s\n' "${HOME}/printer_data/moonraker.asvc" ;;
            *)                 printf '%s\n' "${HOME}/printer_data/config/${f}" ;;
        esac
    }

    install_one() {
        local f="$1"
        local src="${HOME}/OpenNept4une/img-config/printer-data/${f}"
        local dst; dst="$(dest_path_for "$f")"

        if [[ ! -f "$src" ]]; then
            printf '%b\n' "${R}Source missing: ${src}${NC}"
            return 1
        fi

        local dstdir; dstdir="$(dirname "$dst")"
        mkdir -p "$dstdir"

        if [[ "$f" == "data.mdb" ]]; then
            mkdir -p "${HOME}/printer_data/config" "${HOME}/printer_data/database"
            local tmp="${HOME}/printer_data/config/data.mdb"
            cp -f "$src" "$tmp"
            mv -f "$tmp" "$dst"
        else
            cp -f "$src" "$dst"
        fi

        printf '%s\n' "${G}${f} installed to ${dst}.${NC}"
    }

    maybe_diff() {
        local f="$1"
        if [[ "$f" == "data.mdb" ]]; then
            printf '%s\n' "${Y}Skipping diff for binary file: ${f}.${NC}"
            return 2
        fi

        local src="${HOME}/OpenNept4une/img-config/printer-data/${f}"
        local cur; cur="$(dest_path_for "$f")"

        if [[ ! -f "$src" ]]; then
            printf '%b\n' "${R}Source missing for diff: ${src}${NC}"
            return 1
        fi
        if [[ ! -f "$cur" ]]; then
            printf '%s\n' "${Y}No current file found for ${f}; nothing to diff.${NC}"
            return 3
        fi

        local out
        out="$(diff -y --suppress-common-lines --width=90 "$src" "$cur" 2>/dev/null || true)"
        if [[ -z "$out" ]]; then
            printf '%s\n' "${G}No differences for ${f}; up-to-date.${NC}"
            return 4
        fi

        printf '%b\n' "${C}Differences for ${f}:${NC}"
        printf '%s\n' "$out"
        return 0
    }

    # ----------------- Prompt / flow -----------------

    local install_configs_var="$auto_yes"
    if [[ "$auto_yes" != "true" ]]; then
        printf '%s\n\n' "The latest configurations include updated settings and features for your printer."
        printf '%s\n\n' "${Y}Recommended on fresh installs or when resetting to defaults.${NC}"
        printf '%b' "${M}Select latest configurations to install?${NC} (y/N): "
        local choice; read -r choice
        [[ $choice =~ ^[Yy]$ ]] && install_configs_var="true"
    fi

    if [[ "$install_configs_var" != "true" ]]; then
        printf '%b\n' "${Y}Installation of latest configurations skipped.${NC}"
        sleep 1
        return 0
    fi

    PS3="Enter the number of the configuration to install (or 'Exit' to finish): "
    local options=("All" "Fluidd web interface Conf" "Moonraker Conf" "KAMP Conf" "Mainsail web interface Conf" "Pico USB-C ADXL Conf" "Klipper DEBUG Addon" "Exit")

    while true; do
        clear_screen
        printf '%b\n' "${C}${OPENNEPT4UNE_ART}${NC}"
        printf '\n%s\n' "Select configurations to install:"
        for i in "${!options[@]}"; do
            printf '%2d) %s\n' $((i+1)) "${options[$i]}"
        done

        local opt
        read -rp "$PS3" opt
        case "$opt" in
            1)
                printf '%s\n' "Installing all configurations..."
                for key in "${!config_files[@]}"; do
                    [[ "$key" == "All" ]] && continue
                    local files="${config_files[$key]}"
                    [[ -z "$files" ]] && continue
                    for file in $files; do
                        install_one "$file" || printf '%b\n' "${R}Failed: ${file}${NC}"
                    done
                done
                printf '\n%s\n' "${G}All configurations installed.${NC}"
                sleep 2
                return 0
                ;;
            2|3|4|5|6|7)
                local opt_name="${options[$((opt-1))]}"
                printf '%s\n' "Installing ${opt_name}..."
                local files="${config_files[$opt_name]}"

                printf '\n%s\n' "${G}Compare/diff current ${opt_name} with latest? (y/n)${NC}"
                local DIFF_CHOICE
                read -r -p "$(printf '%b' "${M}Enter your choice ${NC}: ")" DIFF_CHOICE

                if [[ "$DIFF_CHOICE" =~ ^[Yy]$ ]]; then
                    clear_screen
                    printf '\n'
                    for file in $files; do
                        printf '%b\n' "${C}==========================================================${NC}"
                        local diff_rc=0
                        maybe_diff "$file" || diff_rc=$?
                        if [[ $diff_rc -eq 0 || $diff_rc -eq 2 || $diff_rc -eq 3 ]]; then
                            printf '\n%s\n' "${Y}Continue with update for ${file}? (y/n)${NC}"
                            local CONTINUE_CHOICE
                            read -r -p "$(printf '%b' "${M}Enter your choice ${NC}: ")" CONTINUE_CHOICE
                            if [[ ! "$CONTINUE_CHOICE" =~ ^[Yy]$ ]]; then
                                printf '%s\n' "${Y}Skipping ${file}.${NC}"
                                continue
                            fi
                        else
                            # up-to-date; skip install
                            continue
                        fi
                        install_one "$file" || printf '%b\n' "${R}Failed: ${file}${NC}"
                    done

                    printf '\n%s\n' "${Y}Install another configuration? (y/n)${NC}"
                    local CONTINUE_CHOICE
                    read -r -p "$(printf '%b' "${M}Enter your choice ${NC}: ")" CONTINUE_CHOICE
                    if [[ "$CONTINUE_CHOICE" =~ ^[Nn]$ ]]; then
                        printf '\n%s\n' "${Y}Exiting the update process.${NC}"
                        sleep 1
                        break
                    fi
                    printf '\n%s\n' "${G}Returning to configuration selection.${NC}"
                    sleep 1
                else
                    printf '\n%s\n' "${G}Continuing with ${opt_name} update.${NC}"
                    sleep 1
                    for file in $files; do
                        install_one "$file" || printf '%b\n' "${R}Failed: ${file}${NC}"
                    done
                fi

                printf '%s\n' "${G}${opt_name} installed successfully.${NC}"
                ;;
            8)
                printf '%s\n' "${Y}Exiting the update process.${NC}"
                break
                ;;
            *)
                printf '%b\n' "${R}Invalid selection. Please try again.${NC}"
                ;;
        esac
    done

    printf '%s\n\n' "${G}Selected configurations installed successfully.${NC}"
    sleep 1
}
