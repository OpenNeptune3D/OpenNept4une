#!/usr/bin/env bash
# Local + CI smoke checks for scripts and generated printer configs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
ok() { printf 'OK: %s\n' "$*"; }

echo "== Python syntax =="
python3 -m py_compile "$ROOT/printer-confs/generate_conf.py"
ok "printer-confs/generate_conf.py compiles"

echo "== Shell syntax (bash -n) =="
scripts=()
while IFS= read -r script; do
    scripts+=("$script")
done < <(find "$ROOT" -name '*.sh' -not -path "$ROOT/.git/*" | sort)
[[ ${#scripts[@]} -gt 0 ]] || fail "no shell scripts found"
for script in "${scripts[@]}"; do
    bash -n "$script" || fail "bash -n $script"
done
ok "${#scripts[@]} scripts passed bash -n"

echo "== Referenced installer scripts exist =="
referenced=(
    "$ROOT/OpenNept4une.sh"
    "$ROOT/img-config/rpi-mcu-install.sh"
    "$ROOT/img-config/usb-storage-automount.sh"
    "$ROOT/img-config/adb-automount.sh"
    "$ROOT/img-config/webcam-setup.sh"
    "$ROOT/img-config/base_image_configuration.sh"
    "$ROOT/img-config/update-ssh-keys.sh"
    "$ROOT/img-config/set-printer-model.sh"
    "$ROOT/img-config/github-issue-debug.sh"
    "$ROOT/img-config/power_monitor.sh"
    "$ROOT/mcu-firmware/alt-method/mcu-swflash-run.sh"
    "$ROOT/mcu-firmware/alt-method/mcu-swflash-install.sh"
    "$ROOT/tests/setup.sh"
    "$ROOT/tests/enable-https.sh"
    "$ROOT/tests/smoke.sh"
)
for path in "${referenced[@]}"; do
    [[ -f "$path" ]] || fail "missing referenced script: $path"
    [[ -s "$path" ]] || fail "empty referenced script: $path"
done
ok "${#referenced[@]} installer paths exist"

echo "== OpenNept4une.sh --help =="
if getopt -T >/dev/null 2>&1; then
    getopt_rc=$?
else
    getopt_rc=$?
fi
# GNU getopt -T returns 4
if [[ "$getopt_rc" -eq 4 ]]; then
    help_out="$(bash "$ROOT/OpenNept4une.sh" --help)"
    printf '%s\n' "$help_out" | grep -q 'Usage:' || fail "help missing Usage:"
    printf '%s\n' "$help_out" | grep -q 'install_printer_cfg' || fail "help missing install_printer_cfg"
    ok "OpenNept4une.sh --help"
else
    echo "SKIP: GNU getopt not available (needed for --help parsing)"
fi

if command -v shellcheck >/dev/null 2>&1; then
    echo "== shellcheck (errors only) =="
    shellcheck --severity=error --shell=bash "${scripts[@]}"
    ok "shellcheck --severity=error"
else
    echo "SKIP: shellcheck not installed"
fi

echo "== generate_conf unit tests =="
python3 -m unittest discover -s "$ROOT/tests" -p 'test_*.py' -v
ok "unittest suite"

echo
echo "All smoke checks passed."
