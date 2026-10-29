#!/bin/bash
# USB-C toolhead power (OpenNept4une#417). Installed as /usr/local/sbin/opennept4une-toolhead-power.
#
# The USB-C printhead runs on a 24 V rail switched by SoC GPIO82 (GPIO2_C2). Elegoo's
# stock image raises it from rc.local; without it the toolhead MCU never enumerates.
# Adapted from dalgibbard's opennept4une-toolhead-power.

set -euo pipefail

GPIO_NUMBER="${TOOLHEAD_POWER_GPIO:-82}"
GPIO_ROOT="${TOOLHEAD_POWER_GPIO_ROOT:-/sys/class/gpio}"
SERIAL_GLOB="${TOOLHEAD_SERIAL_GLOB:-/dev/serial/by-id/usb-Klipper_stm32f103xe_*}"
EXPORT_WAIT_SECONDS=5
GPIO_PATH="${GPIO_ROOT}/gpio${GPIO_NUMBER}"

die() {
    echo "opennept4une-toolhead-power: $*" >&2
    exit 1
}

usage() {
    echo "Usage: $0 {on|off|cycle [seconds]|wait [seconds]|status}" >&2
    exit 2
}

ensure_exported() {
    local waited=0

    [[ -e "${GPIO_ROOT}/export" ]] || die "GPIO sysfs interface is unavailable at ${GPIO_ROOT}"

    if [[ ! -d "$GPIO_PATH" ]]; then
        # EBUSY means another process exported the line between the test and the write;
        # a line claimed by a kernel driver never appears and fails below.
        printf '%s\n' "$GPIO_NUMBER" > "${GPIO_ROOT}/export" 2>/dev/null || true
    fi

    while [[ ! -w "${GPIO_PATH}/direction" || ! -w "${GPIO_PATH}/value" ]]; do
        (( waited >= EXPORT_WAIT_SECONDS )) && die "GPIO ${GPIO_NUMBER} could not be exported (in use by a driver?)"
        sleep 1
        ((waited += 1))
    done
}

set_level() {
    local level="$1"

    ensure_exported
    if [[ "$(<"${GPIO_PATH}/direction")" != "out" ]]; then
        # Writing "high"/"low" sets output direction and level together, with no glitch
        if [[ "$level" = "1" ]]; then
            printf 'high\n' > "${GPIO_PATH}/direction"
        else
            printf 'low\n' > "${GPIO_PATH}/direction"
        fi
    else
        printf '%s\n' "$level" > "${GPIO_PATH}/value"
    fi

    [[ "$(<"${GPIO_PATH}/value")" = "$level" ]] || die "failed to set GPIO ${GPIO_NUMBER} to ${level}"
}

toolhead_present() {
    compgen -G "$SERIAL_GLOB" >/dev/null
}

check_seconds() {
    [[ "$1" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "invalid number of seconds: $1"
}

case "${1:-}" in
    on|high)
        set_level 1
        ;;
    off|low)
        set_level 0
        ;;
    cycle)
        delay="${2:-1}"
        check_seconds "$delay"
        set_level 0
        # Never leave the toolhead unpowered if interrupted mid-cycle
        trap 'set_level 1' EXIT INT TERM
        sleep "$delay"
        trap - EXIT INT TERM
        set_level 1
        ;;
    wait)
        # The toolhead bootloader runs for about ten seconds after power-up before the
        # Klipper application enumerates.
        timeout="${2:-20}"
        [[ "$timeout" =~ ^[0-9]+$ ]] || die "invalid number of seconds: $timeout"
        for (( i = 0; i < timeout; i++ )); do
            toolhead_present && exit 0
            sleep 1
        done
        toolhead_present || die "no USB-C toolhead at ${SERIAL_GLOB} after ${timeout}s"
        ;;
    status)
        if [[ -e "${GPIO_PATH}/value" ]]; then
            printf 'gpio=%s direction=%s value=%s\n' \
                "$GPIO_NUMBER" "$(<"${GPIO_PATH}/direction")" "$(<"${GPIO_PATH}/value")"
        else
            printf 'gpio=%s not exported\n' "$GPIO_NUMBER"
        fi
        if toolhead_present; then
            printf 'toolhead=%s\n' "$(compgen -G "$SERIAL_GLOB" | head -n 1)"
        else
            printf 'toolhead=absent\n'
        fi
        ;;
    *)
        usage
        ;;
esac
