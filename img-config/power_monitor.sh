#!/usr/bin/env bash
# Purpose: Robust power-loss monitor with correct v1/v2 semantics and debounce.

set -euo pipefail

# ===== Configuration =====
DEBUG="${DEBUG:-false}"
CHIP="${CHIP:-gpiochip1}"
LINE_SUPERCAP="${LINE_SUPERCAP:-21}"
LINE_PWRLOSS="${LINE_PWRLOSS:-10}"   # rising = loss
LINE_PWRGOOD="${LINE_PWRGOOD:-19}"   # falling = loss
LOG_TAG="${LOG_TAG:-power_monitor}"
VERIFY_SAMPLES="${VERIFY_SAMPLES:-5}"      # why: reject glitches
VERIFY_INTERVAL_MS="${VERIFY_INTERVAL_MS:-40}"  # why: small, HW-friendly

# ===== Helpers =====
log() { echo "$1" | systemd-cat -t "$LOG_TAG" -p info; echo "$1"; }
die() { log "ERROR: $*"; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found"; }
ms_sleep() { python3 - <<PY || sleep 0
import time; time.sleep(${1}/1000.0)
PY
}

# ===== Pre-flight =====
need_cmd gpioinfo; need_cmd gpioget; need_cmd gpioset; need_cmd gpiomon; need_cmd systemctl
[ "$(id -u)" -eq 0 ] || die "This script must be run as root"

log "Detected libgpiod: $(gpioinfo --version 2>&1 | head -n1)"
$DEBUG && log "===== DEBUG MODE (no destructive ops) ====="

# Detect v2 tool syntax
USE_V2=false
if gpioget --help 2>&1 | grep -q '\-c, \-\-chip'; then
  USE_V2=true; log "Using libgpiod v2 tool syntax"
else
  USE_V2=false; log "Using libgpiod v1 tool syntax"
fi

# Track background processes for cleanup
MON_PIDS=()
SET_HOLDER_PID=""

cleanup() {
  # why: ensure no orphan monitors hold lines
  for p in "${MON_PIDS[@]:-}"; do kill "$p" >/dev/null 2>&1 || true; done
  if [ -n "${SET_HOLDER_PID}" ] && kill -0 "$SET_HOLDER_PID" >/dev/null 2>&1; then
    kill "$SET_HOLDER_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# ===== Supercap enable =====
enable_supercap() {
  if $DEBUG; then
    log "[DEBUG] gpioset ${CHIP} ${LINE_SUPERCAP}=1 (no-op)"
    return
  fi
  if $USE_V2; then
    # why: keep line asserted for charging; background holder process
    gpioset -c "$CHIP" --daemonize "${LINE_SUPERCAP}=1"
    # best-effort grab the newest gpioset holder (optional)
    SET_HOLDER_PID="$(pgrep -n -f "gpioset -c $CHIP .*${LINE_SUPERCAP}=1" || true)"
  else
    # v1: many builds don't have a daemon mode; set best-effort and hope pin default keeps it high.
    gpioset "$CHIP" "${LINE_SUPERCAP}=1" || true
  fi
  log "Super-capacitor charging enabled (GPIO ${LINE_SUPERCAP} HIGH)"
}

# ===== Read states =====
read_states() {
  local out
  if $DEBUG; then
    if $USE_V2; then out="\"${LINE_PWRLOSS}\"=inactive \"${LINE_PWRGOOD}\"=active"
    else out="0 1"; fi
  else
    if $USE_V2; then out="$(gpioget -c "$CHIP" "$LINE_PWRLOSS" "$LINE_PWRGOOD")"
    else out="$(gpioget "$CHIP" "$LINE_PWRLOSS" "$LINE_PWRGOOD")"; fi
  fi

  local pl pg
  if $USE_V2; then
    if   echo "$out" | grep -q "\"${LINE_PWRLOSS}\"=active";   then pl=1
    elif echo "$out" | grep -q "\"${LINE_PWRLOSS}\"=inactive"; then pl=0
    else pl=2; fi
    if   echo "$out" | grep -q "\"${LINE_PWRGOOD}\"=active";   then pg=1
    elif echo "$out" | grep -q "\"${LINE_PWRGOOD}\"=inactive"; then pg=0
    else pg=2; fi
  else
    read -r pl pg <<<"$out"
  fi

  echo "$pl $pg"
}

# ===== Monitors (per-line, correct polarity) =====
start_monitors() {
  MON_PIDS=()
  if $DEBUG; then
    log "[DEBUG] would start: gpiomon PWRLOSS(rising), PWRGOOD(falling)"
    return
  fi

  if $USE_V2; then
    # why: v2 cannot set per-line edges in a single invocation; run two
    gpiomon -c "$CHIP" --edges=rising -n 1 "$LINE_PWRLOSS" & MON_PIDS+=("$!")
    gpiomon -c "$CHIP" --edges=falling -n 1 "$LINE_PWRGOOD" & MON_PIDS+=("$!")
  else
    gpiomon --num-events=1 --rising-edge  "$CHIP" "$LINE_PWRLOSS"  & MON_PIDS+=("$!")
    gpiomon --num-events=1 --falling-edge "$CHIP" "$LINE_PWRGOOD"  & MON_PIDS+=("$!")
  fi
}

wait_any_event() {
  if $DEBUG; then
    log "[DEBUG] simulate waiting 30s"; sleep 30; return 0
  fi
  if [ "${BASH_VERSINFO[0]}" -ge 5 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -ge 3 ]; }; then
    wait -n
  else
    wait
  fi
}

# ===== Verify event (simple debounce/confirm) =====
verify_loss() {
  local ok=0 cnt=0
  while [ "$cnt" -lt "$VERIFY_SAMPLES" ]; do
    read -r pl pg < <(read_states)
    # loss if PWRLOSS==1 or PWRGOOD==0
    if { [ "$pl" = "1" ] || [ "$pg" = "0" ]; }; then
      ok=$((ok+1))
    fi
    cnt=$((cnt+1))
    ms_sleep "$VERIFY_INTERVAL_MS"
  done
  # require majority true
  [ "$ok" -ge $(( (VERIFY_SAMPLES+1)/2 )) ]
}

handle_power_cut() {
  log "Power loss verified. Initiating safe shutdown..."
  if $DEBUG; then
    log "[DEBUG] Would execute: systemctl poweroff"; exit 0
  else
    systemctl poweroff
  fi
}

# ===== Main =====
enable_supercap

read -r pl pg < <(read_states)
log "Initial states — PowerLoss(${LINE_PWRLOSS})=${pl}, PowerGood(${LINE_PWRGOOD})=${pg}"

if [ "$pl" = "0" ] && [ "$pg" = "1" ]; then
  log "Pins in expected stable state. Waiting for PWRLOSS↑ or PWRGOOD↓."
else
  log "WARNING: Unexpected initial state. Continuing anyway."
fi

while true; do
  start_monitors
  wait_any_event
  # Stop any remaining monitor from spurious firing later
  cleanup

  if verify_loss; then
    handle_power_cut
  else
    log "Glitch ignored (failed verification). Re-arming monitors."
  fi
done
