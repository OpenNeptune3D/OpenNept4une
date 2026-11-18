#!/bin/bash
# Script location $HOME/OpenNept4une/img-config/set-printer-model.sh

# Define the flag file path
FLAG_FILE="/boot/.OpenNept4une.txt"

# Function to select an option
select_option() {
    local -n ref=$1
    echo -e "$2"
    select opt in "${@:3}"; do
        if [[ -n $opt ]]; then
            ref=$opt
            break
        else
            echo -e "Invalid option, please try again."
        fi
    done
}

# Headless operation checks
if [ "$auto_yes" = "true" ]; then
    if [[ "$model_key" = "n4" || "$model_key" = "n4pro" ]] && [[ -z "$motor_current" || -z "$pcb_version" ]]; then
        echo "Headless mode for n4 and n4pro requires --motor_current and --pcb_version."
        exit 1
    elif [ -z "$model_key" ]; then
        echo "Headless mode requires --printer_model."
        exit 1
    fi
else
    # Interactive mode for model selection
    echo "Please select your printer model:"
    select _ in "Neptune4" "Neptune4 Pro" "Neptune4 Plus" "Neptune4 Max"; do
        case $REPLY in
            1) model_key="n4";;
            2) model_key="n4pro";;
            3) model_key="n4plus";;
            4) model_key="n4max";;
            *) echo "Invalid selection. Please try again."; continue;;
        esac
        break
    done
    # Interactive mode for motor current and PCB version if applicable
    if [[ "$model_key" = "n4" || "$model_key" = "n4pro" ]]; then
        [ -z "$motor_current" ] && select_option motor_current "Select the stepper motor current:" "0.8" "1.2"
        [ -z "$pcb_version" ] && select_option pcb_version "Select the PCB version:" "1.0" "1.1" "1.4"
    else
        [ -z "$pcb_version" ] && select_option pcb_version "Select the PCB version:" "2.0" "2.3"
    fi

    # Interactive selection of printhead/toolhead variant (applies to all models)
    # The USB-C toolhead is not checked for here: it only appears on USB once its
    # power (GPIO82) is switched on, which happens after the choice is saved.
    if [ -z "$toolhead_variant" ]; then
        select_option toolhead_variant "Select your printhead/toolhead type:" "Ribbon-cable printhead (original)" "USB-C Klipper printhead (separate toolhead MCU)"
        case "$toolhead_variant" in
            "USB-C Klipper printhead (separate toolhead MCU)") toolhead_variant="usb-c" ;;
            *) toolhead_variant="ribbon" ;;
        esac
    fi
fi

# Default/normalize toolhead_variant for headless mode (backward compatible:
# if not provided, assume the original ribbon-cable printhead).
case "$toolhead_variant" in
    usb-c|usbc) toolhead_variant="usb-c" ;;
    *) toolhead_variant="ribbon" ;;
esac

# Only an answered or --pcb_version PCB may change the boot DTB; the "2.0"
# default below is a guess and must not move a V2.3 board off its DTB.
pcb_explicit="$pcb_version"

# Define FLAG_LINE before generating configuration
if [[ "$model_key" = "n4" || "$model_key" = "n4pro" ]]; then
    FLAG_LINE="${model_key}-${motor_current}A-v${pcb_version}"
else
    [ -z "$pcb_version" ] && pcb_version="2.0"
    FLAG_LINE="${model_key}-v${pcb_version}"
fi

# Capitalize the 1st and 3rd letters of the model_key
FLAG_LINE=$(echo "$FLAG_LINE" | sed -E 's/^(n)(4)(.)(.*)/\U\1\2\3\E\4/')

# Append the toolhead variant ("ribbon" or "usb-c" -> "usbc") so OpenNept4une.sh
# can regenerate the right printer.cfg on headless reflashes without re-asking.
toolhead_suffix="ribbon"
[ "$toolhead_variant" = "usb-c" ] && toolhead_suffix="usbc"
FLAG_LINE="${FLAG_LINE}-t${toolhead_suffix}"

echo "DEBUG: FLAG_LINE is $FLAG_LINE"

# Function to update the flag file
update_flag_file() {
    local flag_value=$1
    # Remove existing lines starting with N4 (case-insensitive), then add the new line
    sudo sed -i '/^n4/I d' "$FLAG_FILE"
    echo "$flag_value" | sudo tee -a "$FLAG_FILE" > /dev/null
}

update_flag_file "$FLAG_LINE"

# Point the bootloader at the DTB for this PCB version, on images that ship
# the ZNP-K1 DTBs (Armbian-ZNP-K1-build). Does nothing on older images:
# - their fdtfile= is not a rk3328-znp-k1-*.dtb (e.g. the rk3328-roc-cc.dtb
#   copy-over method), or there is no armbianEnv.txt;
# - the wanted DTB is not in /boot/dtb/rockchip.
# A DTB that already suits the PCB (e.g. n4-v1.1 for V1.1) is kept.
ARMBIAN_ENV="${ARMBIAN_ENV:-/boot/armbianEnv.txt}"
DTB_DIR="${DTB_DIR:-/boot/dtb/rockchip}"
set_board_dtb() {
    local pcb="$1" suitable current current_name wanted f
    case "$pcb" in
        1.0) suitable="rk3328-znp-k1-v1x.dtb rk3328-znp-k1-n4-v1.0.dtb" ;;
        1.1) suitable="rk3328-znp-k1-v1x.dtb rk3328-znp-k1-n4-v1.1.dtb" ;;
        1.4) suitable="rk3328-znp-k1-n4-v1.4.dtb" ;;
        2.0) suitable="rk3328-znp-k1-v2x.dtb rk3328-znp-k1-n4plus-n4max.dtb" ;;
        2.3) suitable="rk3328-znp-k1-n4plus-n4max-v2.3.dtb" ;;
        *) return 0 ;;
    esac
    [ -f "$ARMBIAN_ENV" ] || return 0
    current=$(sed -n 's/^fdtfile=//p' "$ARMBIAN_ENV" | head -n 1)
    current_name="${current##*/}"
    case "$current_name" in
        rk3328-znp-k1-*.dtb) ;;
        *) return 0 ;;
    esac
    for f in $suitable; do
        [ "$f" = "$current_name" ] && return 0
    done
    wanted="${suitable%% *}"
    if [ ! -f "$DTB_DIR/$wanted" ]; then
        echo "Note: $wanted is not in this image; keeping $current_name."
        return 0
    fi
    # Keep the directory prefix (e.g. "rockchip/") of the current value.
    if sudo sed -i "s|^fdtfile=.*|fdtfile=${current%"$current_name"}${wanted}|" "$ARMBIAN_ENV"; then
        sync
        echo -e "\nBoard DTB set for PCB v${pcb}: ${current_name} -> ${wanted}"
        echo "REBOOT before printing (sudo reboot) so the board uses it."
        echo "To undo: set fdtfile=${current} in ${ARMBIAN_ENV} and reboot."
    else
        echo "Warning: could not update ${ARMBIAN_ENV}; keeping ${current_name}."
    fi
    return 0
}
[ -n "$pcb_explicit" ] && set_board_dtb "$pcb_explicit"

# Check the contents of the FLAG_FILE
#echo "DEBUG: Contents of $FLAG_FILE"
#sudo cat "$FLAG_FILE"
sync
exit 0
