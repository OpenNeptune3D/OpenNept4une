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
        [ -z "$pcb_version" ] && select_option pcb_version "Select the PCB version:" "1.0" "1.1"
    fi
fi

# Define FLAG_LINE before generating configuration
if [[ "$model_key" = "n4" || "$model_key" = "n4pro" ]]; then
    FLAG_LINE="${model_key}-${motor_current}A-v${pcb_version}"
else
    pcb_version="2.0"
    FLAG_LINE="${model_key}-v${pcb_version}"
fi

# Capitalize the 1st and 3rd letters of the model_key
FLAG_LINE=$(echo "$FLAG_LINE" | sed -E 's/^(n)(4)(.)(.*)/\U\1\2\3\E\4/')

echo "DEBUG: FLAG_LINE is $FLAG_LINE"

# Function to update the flag file
update_flag_file() {
    local flag_value=$1
    # Remove existing lines starting with N4 (case-insensitive), then add the new line
    sudo sed -i '/^n4/I d' "$FLAG_FILE"
    echo "$flag_value" | sudo tee -a "$FLAG_FILE" > /dev/null
}

update_flag_file "$FLAG_LINE"

# Check the contents of the FLAG_FILE
#echo "DEBUG: Contents of $FLAG_FILE"
#sudo cat "$FLAG_FILE"
sync
exit 0
