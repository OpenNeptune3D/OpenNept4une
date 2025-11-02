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
VERIFY_SAMPLES="${VERIFY_SAMPLES:-5}"
VERIFY_INTERVAL_MS="${VERIFY_INTERVAL_MS:-40}"

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
SUPERCAP_PID=""

cleanup() {
  # Kill monitors on exit
  for p in "${MON_PIDS[@]:-}"; do 
    kill "$p" >/dev/null 2>&1 || true
  done
  # Kill supercap holder if it exists
  if [ -n "${SUPERCAP_PID}" ] && kill -0 "$SUPERCAP_PID" >/dev/null 2>&1; then
    kill "$SUPERCAP_PID" >/dev/null 2>&1 || true
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
    # v2: daemonize mode keeps the line held
    gpioset -c "$CHIP" --daemonize "${LINE_SUPERCAP}=1"
    sleep 0.2  # Give daemon time to fork
    # Try to find PID (best-effort for cleanup)
    SUPERCAP_PID="$(pgrep -n -x gpioset || true)"
    log "Super-capacitor charging enabled (GPIO ${LINE_SUPERCAP} HIGH) [v2 daemonized]"
  else
    # v1: Run gpioset in background to HOLD the line (like your working script)
    gpioset "$CHIP" "${LINE_SUPERCAP}=1" &
    SUPERCAP_PID=$!
    log "Super-capacitor charging enabled (GPIO ${LINE_SUPERCAP} HIGH) [v1, pid=${SUPERCAP_PID}]"
  fi
}

# ===== Read states =====
read_states() {
  local out
  if $DEBUG; then
    if $USE_V2; then out="\"${LINE_PWRLOSS}\"=inactive \"${LINE_PWRGOOD}\"=active"
    else out="0 1"; fi
  else
    if $USE_V2; then out="$(gpioget -c "$CHIP" "$LINE_PWRLOSS" "$LINE_PWRGOOD" 2>&1)"
    else out="$(gpioget "$CHIP" "$LINE_PWRLOSS" "$LINE_PWRGOOD")"; fi
  fi

  local pl pg
  if $USE_V2; then
    # Handle both "LINE"=state and chip LINE=state formats
    if echo "$out" | grep -Eq "(\"${LINE_PWRLOSS}\"|${CHIP}[[:space:]]+${LINE_PWRLOSS})=active"; then pl=1
    elif echo "$out" | grep -Eq "(\"${LINE_PWRLOSS}\"|${CHIP}[[:space:]]+${LINE_PWRLOSS})=inactive"; then pl=0
    else 
      log "WARNING: Could not parse PWRLOSS from: $out"
      pl=2
    fi
    
    if echo "$out" | grep -Eq "(\"${LINE_PWRGOOD}\"|${CHIP}[[:space:]]+${LINE_PWRGOOD})=active"; then pg=1
    elif echo "$out" | grep -Eq "(\"${LINE_PWRGOOD}\"|${CHIP}[[:space:]]+${LINE_PWRGOOD})=inactive"; then pg=0
    else 
      log "WARNING: Could not parse PWRGOOD from: $out"
      pg=2
    fi
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
    # v2: separate invocations for different edge directions
    gpiomon -c "$CHIP" --edges=rising -n 1 "$LINE_PWRLOSS" &
    local pid1=$!
    MON_PIDS+=("$pid1")
    
    gpiomon -c "$CHIP" --edges=falling -n 1 "$LINE_PWRGOOD" &
    local pid2=$!
    MON_PIDS+=("$pid2")
    
    # Verify monitors started
    sleep 0.1
    if ! kill -0 "$pid1" 2>/dev/null || ! kill -0 "$pid2" 2>/dev/null; then
      die "Failed to start v2 monitors"
    fi
    
    log "Monitors started: PWRLOSS(${LINE_PWRLOSS}↑ pid=$pid1) PWRGOOD(${LINE_PWRGOOD}↓ pid=$pid2)"
  else
    # v1: classic syntax (like your working script)
    gpiomon --num-events=1 --rising-edge "$CHIP" "$LINE_PWRLOSS" & MON_PIDS+=("$!")
    gpiomon --num-events=1 --falling-edge "$CHIP" "$LINE_PWRGOOD" & MON_PIDS+=("$!")
    log "Monitors started: PWRLOSS(${LINE_PWRLOSS}↑) and PWRGOOD(${LINE_PWRGOOD}↓), PIDs: ${MON_PIDS[*]}"
  fi
}

wait_any_event() {
  if $DEBUG; then
    log "[DEBUG] simulate waiting 30s"; sleep 30; return 0
  fi
  
  # Wait for ANY monitor to finish
  if [ "${BASH_VERSINFO[0]}" -ge 5 ] || { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]}" -ge 3 ]; }; then
    wait -n "${MON_PIDS[@]}"
  else
    wait
  fi
}

# ===== Verify event (simple debounce/confirm) =====
verify_loss() {
  local ok=0 cnt=0
  log "Verifying power loss condition..."
  
  while [ "$cnt" -lt "$VERIFY_SAMPLES" ]; do
    read -r pl pg < <(read_states)
    # Loss if PWRLOSS==1 or PWRGOOD==0
    if [ "$pl" = "1" ] || [ "$pg" = "0" ]; then
      ok=$((ok+1))
    fi
    cnt=$((cnt+1))
    [ "$cnt" -lt "$VERIFY_SAMPLES" ] && ms_sleep "$VERIFY_INTERVAL_MS"
  done
  
  log "Verification: ${ok}/${VERIFY_SAMPLES} samples confirmed loss"
  # Require majority true
  [ "$ok" -ge $(( (VERIFY_SAMPLES+1)/2 )) ]
}

handle_power_cut() {
  log "Power loss verified. Initiating safe shutdown..."
  if $DEBUG; then
    log "[DEBUG] Would execute: systemctl poweroff"
  else
    systemctl poweroff
  fi
  # Don't exit in real mode - let systemd handle it
  $DEBUG && exit 0
}

# ===== Main =====
enable_supercap

# Give supercap a moment to stabilize
sleep 0.5

read -r pl pg < <(read_states)
log "Initial states — PowerLoss(${LINE_PWRLOSS})=${pl}, PowerGood(${LINE_PWRGOOD})=${pg}"

if [ "$pl" = "0" ] && [ "$pg" = "1" ]; then
  log "Pins in expected stable state. Starting monitors."
else
  log "WARNING: Unexpected initial state (PWRLOSS=${pl}, PWRGOOD=${pg}). Continuing anyway."
fi

# Start monitors once and wait (like your working script)
start_monitors
wait_any_event

# An event occurred - verify it
if verify_loss; then
  handle_power_cut
else
  log "Glitch detected and ignored. Restarting monitors."
  # Only loop if it was a false alarm
  exec "$0" "$@"
fi
