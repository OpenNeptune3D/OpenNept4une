#!/usr/bin/env bash
# Provision an Ubuntu Server or Raspberry Pi host sandbox for OpenNept4une.
# This is the Klipper/Moonraker/Fluidd host only. It is not the printer MCU.
set -euo pipefail

FORCE="false"
SKIP_APT="false"

usage() {
    cat <<'EOF'
Usage: sudo ./tests/setup.sh [OPTIONS]

Install Klipper, Moonraker, Fluidd, KAMP, and generated OpenNept4une configs
on an Ubuntu/Pi host sandbox (Parallels ARM64 VM or Raspberry Pi 4/5).

Options:
  --force      Allow running on a real OpenNept4une printer image
  --skip-apt   Skip apt-get update/install (re-run after packages exist)
  -h, --help   Show this help

Run as a normal user via sudo, not as a login root shell:
  sudo ./tests/setup.sh
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force) FORCE="true"; shift ;;
        --skip-apt) SKIP_APT="true"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Error: run with sudo:  sudo $0" >&2
    exit 1
fi
if [[ -z "${SUDO_USER:-}" || "${SUDO_USER}" = "root" ]]; then
    echo "Error: do not run as plain root. Run via sudo from your normal user." >&2
    exit 1
fi

die() { echo "Error: $*" >&2; exit 1; }
ok() { echo "==> $*"; }

if [[ -f /boot/.OpenNept4une.txt && "$FORCE" != "true" ]]; then
    die "Refusing to run on an OpenNept4une printer image. Pass --force if you meant to."
fi

TARGET_USER="${SUDO_USER}"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"
[[ -n "$TARGET_HOME" ]] || die "Cannot resolve home for $TARGET_USER"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/../printer-confs/generate_conf.py" ]]; then
    REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
else
    REPO_DIR="${TARGET_HOME}/OpenNept4une"
fi

OPENNEPT4UNE_REPO="${OPENNEPT4UNE_REPO:-https://github.com/OpenNeptune3D/OpenNept4une.git}"
KLIPPER_REPO="${KLIPPER_REPO:-https://github.com/Klipper3d/klipper.git}"
MOONRAKER_REPO="${MOONRAKER_REPO:-https://github.com/Arksine/moonraker.git}"
KAMP_REPO="${KAMP_REPO:-https://github.com/kyleisah/Klipper-Adaptive-Meshing-Purging.git}"
KIAUH_REPO="${KIAUH_REPO:-https://github.com/dw-0/kiauh.git}"
FLUIDD_ZIP="${FLUIDD_ZIP:-https://github.com/fluidd-core/fluidd/releases/latest/download/fluidd.zip}"

KLIPPER_DIR="${TARGET_HOME}/klipper"
MOONRAKER_DIR="${TARGET_HOME}/moonraker"
FLUIDD_DIR="${TARGET_HOME}/fluidd"
KAMP_DIR="${TARGET_HOME}/Klipper-Adaptive-Meshing-Purging"
KIAUH_DIR="${TARGET_HOME}/kiauh"
PDIR="${TARGET_HOME}/printer_data"
PCONFIG="${PDIR}/config"
PLOGS="${PDIR}/logs"
PGEN="${PCONFIG}/generated"

as_user() {
    sudo -u "$TARGET_USER" --preserve-env=HOME env HOME="$TARGET_HOME" "$@"
}

clone_or_update() {
    local url="$1" dest="$2"
    if [[ -d "${dest}/.git" ]]; then
        ok "Updating ${dest}"
        as_user git -C "$dest" pull --ff-only || true
    else
        ok "Cloning ${url}"
        as_user git clone --depth=1 "$url" "$dest"
    fi
}

export DEBIAN_FRONTEND=noninteractive

if [[ "$SKIP_APT" != "true" ]]; then
    ok "Installing apt packages"
    apt-get update
    apt-get install -y \
        git wget curl unzip sudo \
        python3 python3-venv python3-dev python3-pip \
        build-essential libffi-dev libncurses-dev libusb-dev \
        libjpeg-dev zlib1g-dev \
        pkg-config virtualenv \
        nginx \
        stm32flash dfu-util \
        gcc-arm-none-eabi binutils-arm-none-eabi libnewlib-arm-none-eabi \
        libopenblas-dev python3-numpy
fi

if [[ ! -f "${REPO_DIR}/printer-confs/generate_conf.py" ]]; then
    clone_or_update "$OPENNEPT4UNE_REPO" "$REPO_DIR"
fi

clone_or_update "$KLIPPER_REPO" "$KLIPPER_DIR"
clone_or_update "$MOONRAKER_REPO" "$MOONRAKER_DIR"
clone_or_update "$KAMP_REPO" "$KAMP_DIR"
clone_or_update "$KIAUH_REPO" "$KIAUH_DIR"

ok "Ensuring printer_data layout"
as_user mkdir -p "$PCONFIG" "$PLOGS" "${PDIR}/gcodes" "${PDIR}/database" "${PDIR}/comms" "$PGEN"
if [[ ! -L "${PCONFIG}/KAMP" ]]; then
    as_user ln -sfn "${KAMP_DIR}/Configuration" "${PCONFIG}/KAMP"
fi

if [[ ! -x "${TARGET_HOME}/klippy-env/bin/python" ]]; then
    ok "Installing Klipper"
    if [[ -x "${KLIPPER_DIR}/scripts/install-ubuntu-22.04.sh" ]]; then
        as_user bash "${KLIPPER_DIR}/scripts/install-ubuntu-22.04.sh"
    else
        die "Klipper install script not found"
    fi
else
    ok "Klipper venv already present; skipping installer"
fi

if [[ ! -f "${PCONFIG}/moonraker.conf" ]]; then
    ok "Writing sandbox moonraker.conf"
    src_moon="${REPO_DIR}/tests/sandbox-moonraker.conf"
    [[ -f "$src_moon" ]] || src_moon="${REPO_DIR}/img-config/printer-data/moonraker.conf"
    sed "s|/home/mks|${TARGET_HOME}|g" "$src_moon" > "${PCONFIG}/moonraker.conf"
    chown "${TARGET_USER}:${TARGET_USER}" "${PCONFIG}/moonraker.conf"
fi

if [[ ! -x "${TARGET_HOME}/moonraker-env/bin/python" ]]; then
    ok "Installing Moonraker"
    as_user bash "${MOONRAKER_DIR}/scripts/install-moonraker.sh" \
        -d "${PDIR}" \
        -c "${PCONFIG}/moonraker.conf" \
        -l "${PLOGS}/moonraker.log"
else
    ok "Moonraker venv already present; skipping installer"
fi

ok "Installing Fluidd"
as_user mkdir -p "$FLUIDD_DIR"
if [[ ! -f "${FLUIDD_DIR}/index.html" ]]; then
    tmpzip="$(as_user mktemp "${TARGET_HOME}/fluidd.XXXXXX.zip")"
    as_user wget -O "$tmpzip" "$FLUIDD_ZIP" || die "Fluidd download failed"
    [[ -s "$tmpzip" ]] || die "Fluidd download was empty"
    as_user unzip -t "$tmpzip" >/dev/null || die "Fluidd zip is not valid"
    as_user unzip -qo "$tmpzip" -d "$FLUIDD_DIR"
    rm -f "$tmpzip"
    [[ -f "${FLUIDD_DIR}/index.html" ]] || die "Fluidd extract did not produce index.html"
else
    ok "Fluidd already present; skipping download"
fi
chown -R "${TARGET_USER}:${TARGET_USER}" "$FLUIDD_DIR"
# nginx (www-data) must be able to traverse the home directory
chmod 755 "$TARGET_HOME"

ok "Configuring nginx for Fluidd"
cat > /etc/nginx/sites-available/fluidd <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root ${FLUIDD_DIR};
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /websocket {
        proxy_pass http://127.0.0.1:7125/websocket;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
    }

    location ~ ^/(printer|api|access|machine|server)/ {
        proxy_pass http://127.0.0.1:7125\$request_uri;
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF
rm -f /etc/nginx/sites-enabled/default
ln -sfn /etc/nginx/sites-available/fluidd /etc/nginx/sites-enabled/fluidd
nginx -t
systemctl enable nginx
systemctl restart nginx

if [[ -x "${SCRIPT_DIR}/enable-https.sh" ]]; then
    ok "Enabling HTTPS"
    bash "${SCRIPT_DIR}/enable-https.sh" || echo "Warning: HTTPS setup failed; HTTP still works"
fi

ok "Building Linux process MCU"
if [[ -f "${REPO_DIR}/mcu-firmware/virtualmcu.config" ]]; then
    as_user cp "${REPO_DIR}/mcu-firmware/virtualmcu.config" "${KLIPPER_DIR}/.config"
    as_user make -C "$KLIPPER_DIR" olddefconfig
    as_user make -C "$KLIPPER_DIR" -j"$(nproc)"
    make -C "$KLIPPER_DIR" flash || echo "Warning: virtual MCU flash/install failed; continuing"
    if [[ -f "${KLIPPER_DIR}/scripts/klipper-mcu.service" ]]; then
        cp "${KLIPPER_DIR}/scripts/klipper-mcu.service" /etc/systemd/system/klipper-mcu.service
        systemctl daemon-reload
        systemctl enable klipper-mcu.service || true
        systemctl restart klipper-mcu.service || true
    fi
fi

ok "Generating OpenNept4une printer configs"
as_user python3 "${REPO_DIR}/printer-confs/generate_conf.py" n4 0.8
as_user cp "${REPO_DIR}/printer-confs/output.cfg" "${PGEN}/n4-0.8.cfg"
as_user python3 "${REPO_DIR}/printer-confs/generate_conf.py" n4 1.2
as_user cp "${REPO_DIR}/printer-confs/output.cfg" "${PGEN}/n4-1.2.cfg"
as_user python3 "${REPO_DIR}/printer-confs/generate_conf.py" n4pro 0.8
as_user cp "${REPO_DIR}/printer-confs/output.cfg" "${PGEN}/n4pro-0.8.cfg"
as_user python3 "${REPO_DIR}/printer-confs/generate_conf.py" n4pro 1.2
as_user cp "${REPO_DIR}/printer-confs/output.cfg" "${PGEN}/n4pro-1.2.cfg"
as_user python3 "${REPO_DIR}/printer-confs/generate_conf.py" n4plus
as_user cp "${REPO_DIR}/printer-confs/output.cfg" "${PGEN}/n4plus.cfg"
as_user python3 "${REPO_DIR}/printer-confs/generate_conf.py" n4max
as_user cp "${REPO_DIR}/printer-confs/output.cfg" "${PGEN}/n4max.cfg"

if [[ ! -f "${PCONFIG}/user_settings.cfg" ]]; then
    as_user tee "${PCONFIG}/user_settings.cfg" >/dev/null <<'EOF'
# Sandbox-only overrides. On a real printer this file is yours to keep
# across OpenNept4une printer.cfg regenerations.
EOF
fi

if [[ ! -f "${PCONFIG}/printer.cfg" ]]; then
    ok "Writing sandbox printer.cfg (Linux MCU, not the Max STM32)"
    as_user tee "${PCONFIG}/printer.cfg" >/dev/null <<'EOF'
# Host-sandbox printer.cfg
# Generated configs for the real Max/Plus/Pro live in generated/.
# This file only has to start klippy on a VM or Pi with no STM32.

[include user_settings.cfg]

[mcu]
serial: /tmp/klipper_host_mcu

[virtual_sdcard]
path: ~/printer_data/gcodes

[display_status]
[pause_resume]
[respond]
[force_move]
enable_force_move: True

[printer]
kinematics: cartesian
max_velocity: 250
max_accel: 3000
max_z_velocity: 8
max_z_accel: 120

[stepper_x]
step_pin: gpiochip0/gpio0
dir_pin: gpiochip0/gpio1
enable_pin: !gpiochip0/gpio2
microsteps: 16
rotation_distance: 40
endstop_pin: gpiochip0/gpio3
position_endstop: 0
position_max: 430
homing_speed: 50

[stepper_y]
step_pin: gpiochip0/gpio4
dir_pin: gpiochip0/gpio5
enable_pin: !gpiochip0/gpio6
microsteps: 16
rotation_distance: 40
endstop_pin: gpiochip0/gpio7
position_endstop: 0
position_max: 430
homing_speed: 50

[stepper_z]
step_pin: gpiochip0/gpio8
dir_pin: gpiochip0/gpio9
enable_pin: !gpiochip0/gpio10
microsteps: 16
rotation_distance: 8
endstop_pin: gpiochip0/gpio11
position_endstop: 0
position_max: 505

[extruder]
step_pin: gpiochip0/gpio12
dir_pin: gpiochip0/gpio13
enable_pin: !gpiochip0/gpio14
microsteps: 16
rotation_distance: 28.888
nozzle_diameter: 0.400
filament_diameter: 1.750
heater_pin: gpiochip0/gpio15
sensor_type: EPCOS 100K B57560G104F
sensor_pin: gpiochip0/gpio16
control: pid
pid_kp: 25.718
pid_ki: 3.297
pid_kd: 50.150
min_temp: 0
max_temp: 330
EOF
fi

chown -R "${TARGET_USER}:${TARGET_USER}" "$PDIR"
# The stock Klipper unit reads ~/printer.cfg, not printer_data/config/printer.cfg
ln -sfn "${PCONFIG}/printer.cfg" "${TARGET_HOME}/printer.cfg"
ln -sfn "${PCONFIG}/user_settings.cfg" "${TARGET_HOME}/user_settings.cfg"
chown -h "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/printer.cfg" "${TARGET_HOME}/user_settings.cfg"

systemctl enable klipper.service 2>/dev/null || true
systemctl enable moonraker.service 2>/dev/null || true
systemctl restart klipper.service 2>/dev/null || true
systemctl restart moonraker.service 2>/dev/null || true

ip_addr="$(hostname -I 2>/dev/null | awk '{print $1}')"
ok "Host sandbox provisioned"
echo
echo "Fluidd:    http://${ip_addr:-GUEST-IP}/"
echo "Moonraker: http://${ip_addr:-GUEST-IP}:7125/"
echo "Generated Max config: ${PGEN}/n4max.cfg"
echo "Active printer.cfg is a Linux-MCU sandbox, not the STM32 Max config."
echo "Kiauh (optional): ${KIAUH_DIR}/kiauh.sh"
echo
echo "If klippy cannot claim gpiochip0 pins, that is expected on some VMs."
echo "Fluidd/Moonraker and generated/*.cfg are still usable for config work."
