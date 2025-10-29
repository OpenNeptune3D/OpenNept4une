#!/bin/bash
# file: power_monitor.sh
# Purpose: Monitor power loss via GPIO lines and safely shut down system.

set -euo pipefail

# ===== Configuration =====
DEBUG="${DEBUG:-false}"                 # set to "true" for dry-run
CHIP="${CHIP:-gpiochip1}"               # GPIO chip device name/num
LINE_SUPERCAP="${LINE_SUPERCAP:-21}"    # GPIO line for supercap charging
LINE_PWRLOSS="${LINE_PWRLOSS:-10}"      # offset for "power loss detect"
LINE_PWRGOOD="${LINE_PWRGOOD:-19}"      # offset for "power good"
LOG_TAG="${LOG_TAG:-power_monitor}"

# ===== Helpers =====
log_message() {
    echo "$1" | systemd-cat -t "$LOG_TAG" -p info
    echo "$1"
}
die() {
    log_message "ERROR: $*"
    exit 1
}
need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found"
}

# ===== Pre-flight =====
need_cmd gpioinfo
need_cmd gpioget
need_cmd gpioset
need_cmd gpiomon
need_cmd systemctl

if [ "$(id -u)" -ne 0 ]; then
    die "This script must be run as root (sudo)"
fi

log_message "Detected libgpiod version: $(gpioinfo --version 2>&1 | head -n1)"

if [ "$DEBUG" = "true" ]; then
    log_message "===== DEBUG MODE ENABLED: dry run only ====="
fi

# ===== Determine syntax/version fallback =====
# We'll assume that if --chip option works for gpioget, we use "v2 style"; else fallback to v1.
USE_V2=false
if gpioget --help 2>&1 | grep -q '\-c, \-\-chip'; then
    USE_V2=true
    log_message "Using libgpiod tool syntax with --chip (v2 style)"
else
    USE_V2=false
    log_message "Using libgpiod tool syntax without --chip (v1 style)"
fi

# ===== Enable super-capacitor charging (GPIO HIGH) =====
if [ "$DEBUG" = "true" ]; then
    log_message "[DEBUG] Would execute: gpioset ${CHIP} ${LINE_SUPERCAP}=1"
else
    if [ "$USE_V2" = "true" ]; then
        gpioset -c "$CHIP" "${LINE_SUPERCAP}=1"
    else
        gpioset "$CHIP" "${LINE_SUPERCAP}=1"
    fi
fi
log_message "Super-capacitor charging enabled (GPIO ${LINE_SUPERCAP} set HIGH)"

# Allow settling
if [ "$DEBUG" = "true" ]; then
    log_message "[DEBUG] Sleeping for 2 seconds"
fi
sleep 2

# ===== Read initial GPIO states =====
if [ "$DEBUG" = "true" ]; then
    if [ "$USE_V2" = "true" ]; then
        INITIAL_STATES='"'"${LINE_PWRLOSS}"'"=inactive "'"${LINE_PWRGOOD}"'"=active'
    else
        INITIAL_STATES="0 1"
    fi
    log_message "[DEBUG] Simulated GPIO read: $INITIAL_STATES"
else
    if [ "$USE_V2" = "true" ]; then
        INITIAL_STATES=$(gpioget -c "$CHIP" "$LINE_PWRLOSS" "$LINE_PWRGOOD")
    else
        INITIAL_STATES=$(gpioget "$CHIP" "$LINE_PWRLOSS" "$LINE_PWRGOOD")
    fi
fi
log_message "Raw GPIO states: $INITIAL_STATES"

# ===== Parse states =====
if [ "$USE_V2" = "true" ]; then
    if echo "$INITIAL_STATES" | grep -q "\"${LINE_PWRLOSS}\"=inactive"; then
        STATE_PWRLOSS="0"
    elif echo "$INITIAL_STATES" | grep -q "\"${LINE_PWRLOSS}\"=active"; then
        STATE_PWRLOSS="1"
    else
        STATE_PWRLOSS="unknown"
    fi

    if echo "$INITIAL_STATES" | grep -q "\"${LINE_PWRGOOD}\"=inactive"; then
        STATE_PWRGOOD="0"
    elif echo "$INITIAL_STATES" | grep -q "\"${LINE_PWRGOOD}\"=active"; then
        STATE_PWRGOOD="1"
    else
        STATE_PWRGOOD="unknown"
    fi
else
    # v1 format: two whitespace-separated values
    read -r STATE_PWRLOSS STATE_PWRGOOD <<< "$INITIAL_STATES"
fi

log_message "Parsed GPIO states — PowerLossDetect(${LINE_PWRLOSS}) = ${STATE_PWRLOSS}, PowerGood(${LINE_PWRGOOD}) = ${STATE_PWRGOOD}"

# ===== Handler =====
handle_power_cut() {
    log_message "Power loss detected! Initiating safe shutdown..."
    if [ "$DEBUG" = "true" ]; then
        log_message "[DEBUG] Would execute: systemctl poweroff"
        exit 0
    else
        systemctl poweroff
    fi
}

# ===== Initial state check =====
if [ "$STATE_PWRLOSS" = "0" ] && [ "$STATE_PWRGOOD" = "1" ]; then
    log_message "GPIO pins in expected stable (power-good) state."
    log_message "  Waiting: PowerLossDetect pin (${LINE_PWRLOSS}) rising edge = loss"
    log_message "           PowerGood pin (${LINE_PWRGOOD}) falling edge = loss"

    # ===== Monitoring =====
    if [ "$DEBUG" = "true" ]; then
        log_message "[DEBUG] Would start monitoring GPIO events..."
        if [ "$USE_V2" = "true" ]; then
            log_message "[DEBUG]   gpiomon --edges=rising ${CHIP} ${LINE_PWRLOSS} &"
            log_message "[DEBUG]   gpiomon --edges=falling ${CHIP} ${LINE_PWRGOOD} &"
        else
            log_message "[DEBUG]   gpiomon --num-events=1 --rising-edge ${CHIP} ${LINE_PWRLOSS} &"
            log_message "[DEBUG]   gpiomon --num-events=1 --falling-edge ${CHIP} ${LINE_PWRGOOD} &"
        fi
        log_message "[DEBUG] Simulating monitoring for 30 seconds then exit..."
        sleep 30
        log_message "[DEBUG] Done dry-run."
        exit 0
    else
        if [ "$USE_V2" = "true" ]; then
            gpiomon --edges=rising "$CHIP" "$LINE_PWRLOSS" &
            gpiomon --edges=falling "$CHIP" "$LINE_PWRGOOD" &
        else
            gpiomon --num-events=1 --rising-edge "$CHIP" "$LINE_PWRLOSS" &
            gpiomon --num-events=1 --falling-edge "$CHIP" "$LINE_PWRGOOD" &
        fi

        # Wait for *any* event (wait -n requires Bash 4.3+)
        if [ "${BASH_VERSINFO[0]}" -ge 5 ] || ([ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -ge 3 ]); then
            wait -n
        else
            wait
        fi
        handle_power_cut
    fi

else
    log_message "WARNING: GPIO pins not in expected initial state!"
    log_message "Expected: ${LINE_PWRLOSS}=0 & ${LINE_PWRGOOD}=1 | Got: ${STATE_PWRLOSS} & ${STATE_PWRGOOD}"
    log_message "Continuing monitoring despite the unexpected state."

    if [ "$DEBUG" = "true" ]; then
        log_message "[DEBUG] Would continue monitoring (dry-run) for 30 seconds..."
        sleep 30
        exit 0
    else
        if [ "$USE_V2" = "true" ]; then
            gpiomon -c "$CHIP" --edges=rising -n 1 -T "$LINE_PWRLOSS" &
            gpiomon -c "$CHIP" --edges=falling -n 1 -T "$LINE_PWRGOOD" &
        else
            gpiomon --num-events=1 --rising-edge "$CHIP" "$LINE_PWRLOSS" &
            gpiomon --num-events=1 --falling-edge "$CHIP" "$LINE_PWRGOOD" &
        fi
        
        if [ "${BASH_VERSINFO[0]}" -ge 5 ] || ([ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -ge 3 ]); then
            wait -n
        else
            wait
        fi
        handle_power_cut
    fi
fi
