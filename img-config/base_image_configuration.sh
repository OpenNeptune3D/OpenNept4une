#!/bin/bash
# Purpose: Prepare a clean Armbian image for Klipper/Fluidd using sudo (not root $HOME)

set -euo pipefail

# ===== Guards =====
if [[ "$(id -u)" -ne 0 ]]; then
  echo "Error: run with sudo:  sudo $0" >&2
  exit 1
fi
if [[ -z "${SUDO_USER:-}" || "${SUDO_USER}" = "root" ]]; then
  echo "Error: do not run as plain root. Run via sudo from your normal user." >&2
  exit 1
fi

# ===== Config (override via env) =====
TARGET_USER="${TARGET_USER:-${SUDO_USER}}"
KAMP_REPO="${KAMP_REPO:-https://github.com/kyleisah/Klipper-Adaptive-Meshing-Purging.git}"
KIAUH_REPO="${KIAUH_REPO:-https://github.com/dw-0/kiauh.git}"
FLUIDD_CONFIG_REPO="${FLUIDD_CONFIG_REPO:-https://github.com/fluidd-core/fluidd-config.git}"
FLUIDD_DB_URL="${FLUIDD_DB_URL:-https://raw.githubusercontent.com/OpenNeptune3D/OpenNept4une/main/img-config/printer-data/data.mdb}"
ARM_ENV_PATH="${ARM_ENV_PATH:-/boot/armbianEnv.txt}"
RUN_KIAUH="${RUN_KIAUH:-1}"
# 1 = after KIAUH, run the OpenNept4une steps (configs, USB mount, screen, Virtual RPi MCU)
RUN_POSTINSTALL="${RUN_POSTINSTALL:-1}"
NETPLAN_FILE="${NETPLAN_FILE:-/etc/netplan/10-dhcp-all-interfaces.yaml}"

# If your repo with spidev fixes is elsewhere, set SPIDEV_SRC_DIR before running:
SPIDEV_SRC_DIR="${SPIDEV_SRC_DIR:-/home/${SUDO_USER}/OpenNept4une/img-config/spidev-fix}"

# ===== Helpers =====
die() { echo "Error: $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }
user_home() {
  local u="$1" h
  h="$(getent passwd "$u" | cut -d: -f6 || true)"
  [[ -n "$h" ]] || die "Cannot resolve home for user '$u'"
  echo "$h"
}

# ===== Preflight =====
need_cmd git
need_cmd wget
need_cmd crontab
need_cmd tee
need_cmd grep
need_cmd getent
need_cmd sed
need_cmd systemctl
need_cmd apt-get
need_cmd sysctl
need_cmd udevadm

TARGET_HOME="$(user_home "$TARGET_USER")"
PDIR="${TARGET_HOME}/printer_data"
PCONFIG="${PDIR}/config"
PDB_DIR="${PDIR}/database"
KAMP_DIR="${TARGET_HOME}/Klipper-Adaptive-Meshing-Purging"
KIAUH_DIR="${TARGET_HOME}/kiauh"
KAMP_LINK="${PCONFIG}/KAMP"
FLUIDD_CONFIG_DIR="${TARGET_HOME}/fluidd-config"
FLUIDD_CFG_LINK="${PCONFIG}/fluidd.cfg"
DB_PATH="${PDB_DIR}/data.mdb"

echo "==> TARGET_USER=${TARGET_USER}"
echo "==> TARGET_HOME=${TARGET_HOME}"

# Images built with the OpenNept4une userpatches/customize-image.sh and
# NETWORKING_STACK=network-manager already have the next two steps done at
# build time. They stay here as fallbacks for other Armbian builds and skip
# themselves when there is nothing to do.

# ===== Load rk805 PMIC driver at boot (for enabling mainboard power LEDs) =====
if [[ -f /etc/modules-load.d/rk805.conf ]]; then
  echo "rk805 module load already configured"
else
  printf "pinctrl-rk805\n" > /etc/modules-load.d/rk805.conf
  echo "Added /etc/modules-load.d/rk805.conf"
fi

# ===== Netplan -> NetworkManager (only if still on systemd-networkd) =====
if [[ ! -f "$NETPLAN_FILE" ]] || ! command -v netplan >/dev/null 2>&1; then
  echo "Warning: netplan not available or $NETPLAN_FILE not found; skipping network changes" >&2
elif ! grep -qE '^\s*renderer:\s*networkd\s*$' "$NETPLAN_FILE"; then
  echo "Network already uses NetworkManager; leaving it unchanged"
elif ! systemctl cat NetworkManager.service >/dev/null 2>&1; then
  # Switching the renderer without NetworkManager installed would leave no network after reboot.
  echo "Warning: NetworkManager is not installed; keeping systemd-networkd" >&2
else
  systemctl enable --now NetworkManager.service
  sed -i 's/^\(\s*renderer:\s*\)networkd\s*$/\1NetworkManager/' "$NETPLAN_FILE"
  echo "Updated renderer to NetworkManager in $NETPLAN_FILE"

  netplan generate
  netplan apply

  systemctl disable --now systemd-networkd.service systemd-networkd.socket systemd-networkd-wait-online.service NetworkManager-wait-online.service || true
  systemctl mask systemd-networkd-wait-online.service || true
fi

# ===== Directories & ownership =====
mkdir -p "${PCONFIG}" "${PDB_DIR}"
chown -R "${TARGET_USER}:${TARGET_USER}" "${PDIR}"

# ===== KAMP clone & link =====
if [[ ! -d "${KAMP_DIR}/.git" ]]; then
  sudo -u "${TARGET_USER}" git clone --depth=1 "${KAMP_REPO}" "${KAMP_DIR}"
else
  sudo -u "${TARGET_USER}" git -C "${KAMP_DIR}" pull --ff-only || true
fi

if [[ ! -L "${KAMP_LINK}" ]]; then
  if [[ -e "${KAMP_LINK}" && ! -L "${KAMP_LINK}" ]]; then
    die "Found non-symlink at ${KAMP_LINK}. Move it away, then re-run."
  fi
  ln -s "${KAMP_DIR}/Configuration" "${KAMP_LINK}"
fi

# ===== fluidd-config clone & link =====
# Full clone (not --depth=1): Moonraker's update_manager [fluidd-config] updates it.
if [[ ! -d "${FLUIDD_CONFIG_DIR}/.git" ]]; then
  sudo -u "${TARGET_USER}" git clone "${FLUIDD_CONFIG_REPO}" "${FLUIDD_CONFIG_DIR}"
else
  sudo -u "${TARGET_USER}" git -C "${FLUIDD_CONFIG_DIR}" pull --ff-only || true
fi

if [[ -e "${FLUIDD_CFG_LINK}" && ! -L "${FLUIDD_CFG_LINK}" ]]; then
  mv "${FLUIDD_CFG_LINK}" "${FLUIDD_CFG_LINK}.bak"
  echo "Moved existing ${FLUIDD_CFG_LINK} to ${FLUIDD_CFG_LINK}.bak"
fi
sudo -u "${TARGET_USER}" ln -sfn "${FLUIDD_CONFIG_DIR}/fluidd.cfg" "${FLUIDD_CFG_LINK}"
echo "Linked ${FLUIDD_CFG_LINK} -> ${FLUIDD_CONFIG_DIR}/fluidd.cfg"

# ===== KIAUH clone =====
if [[ ! -d "${KIAUH_DIR}/.git" ]]; then
  sudo -u "${TARGET_USER}" git clone --depth=1 "${KIAUH_REPO}" "${KIAUH_DIR}"
else
  sudo -u "${TARGET_USER}" git -C "${KIAUH_DIR}" pull --ff-only || true
fi

# ===== Fluidd DB =====
if [[ ! -f "${DB_PATH}" ]]; then
  sudo -u "${TARGET_USER}" wget -O "${DB_PATH}.tmp" "${FLUIDD_DB_URL}"
  mv "${DB_PATH}.tmp" "${DB_PATH}"
  echo "Downloaded ${DB_PATH}"
else
  echo "${DB_PATH} already exists; skipping download"
fi
chown -R "${TARGET_USER}:${TARGET_USER}" "${PDB_DIR}"

# ===== Armbian extraargs merge =====
# net.ifnames=0: classic eth0/wlan0 interface names.
# rt_group_sched=0: kernels built with CONFIG_RT_GROUP_SCHED=y give every
#   systemd service a real-time budget of 0, so klipper_mcu -r fails with
#   "sched_setscheduler: Operation not permitted" (exit 255). Needs kernel
#   6.16+ and a reboot.
touch "${ARM_ENV_PATH}"
grep -q '^extraargs=' "${ARM_ENV_PATH}" || printf 'extraargs=\n' >> "${ARM_ENV_PATH}"
for arg in net.ifnames=0 rt_group_sched=0; do
  if grep -q "^extraargs=\(.* \)\?${arg//./\\.}\( .*\)\?$" "${ARM_ENV_PATH}"; then
    echo "extraargs already contains ${arg}"
  else
    sed -i "s/^extraargs=.*/& ${arg}/; s/^extraargs= /extraargs=/" "${ARM_ENV_PATH}"
    echo "Updated ${ARM_ENV_PATH} (added ${arg})"
  fi
done

# ===== System maintenance (no log wiping) =====
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y upgrade
apt-get -y autoremove
apt-get autoclean
apt-get clean

# ===== Groups and udev for gpio/spi/serial =====
if ! getent group gpio >/dev/null; then groupadd gpio; fi
usermod -a -G gpio "${TARGET_USER}"
GPIO_RULE='/etc/udev/rules.d/99-gpio.rules'
if [[ ! -f "${GPIO_RULE}" ]]; then
  printf 'SUBSYSTEM=="gpio", KERNEL=="gpiochip*", GROUP="gpio", MODE="0660"\n' | tee "${GPIO_RULE}" >/dev/null
fi

if ! getent group spiusers >/dev/null; then groupadd spiusers; fi
usermod -a -G spiusers "${TARGET_USER}"
SPIDEV_RULE='/etc/udev/rules.d/99-spidev.rules'
if [[ ! -f "${SPIDEV_RULE}" ]]; then
  printf 'SUBSYSTEM=="spidev", GROUP="spiusers", MODE="0660"\n' | tee "${SPIDEV_RULE}" >/dev/null
fi

# Serial MCU devices (/dev/ttyACM*, /dev/ttyUSB*) typically need dialout
usermod -a -G dialout "${TARGET_USER}"

udevadm control --reload-rules || true
udevadm trigger --subsystem-match=gpio --action=add || true
udevadm trigger --subsystem-match=spidev --action=add || true

# ===== spidev fix files (best-effort, optional, if you un-comment) =====
#ROCKCHIP_DIR="/boot/dtb/rockchip/overlay"
#mkdir -p "${ROCKCHIP_DIR}"
#if [[ -f "${SPIDEV_SRC_DIR}/99-spidev.rules" ]]; then
#  cp "${SPIDEV_SRC_DIR}/99-spidev.rules" /etc/udev/rules.d/
#else
#  echo "WARN: ${SPIDEV_SRC_DIR}/99-spidev.rules not found; skipping"
#fi
#for f in rockchip-fixup.scr rockchip-spi-spidev.dtbo; do
#  if [[ -f "${SPIDEV_SRC_DIR}/${f}" ]]; then
#    cp "${SPIDEV_SRC_DIR}/${f}" "${ROCKCHIP_DIR}/"
#  else
#    echo "WARN: ${SPIDEV_SRC_DIR}/${f} not found; skipping"
#  fi
#done

# ===== Kernel RT budget (left as-is; uncomment if you want RT unlimited) =====
# Not a fix for klipper_mcu's "sched_setscheduler: Operation not permitted":
# that is rt_group_sched=0 in extraargs above.
#SYSCTL_DROPIN="/etc/sysctl.d/10-disable-rt-group-limit.conf"
#if ! grep -qs '^kernel\.sched_rt_runtime_us' "${SYSCTL_DROPIN}" 2>/dev/null; then
#  printf 'kernel.sched_rt_runtime_us = -1\n' | tee "${SYSCTL_DROPIN}" >/dev/null
#else
#  sed -i 's/^kernel\.sched_rt_runtime_us.*/kernel.sched_rt_runtime_us = -1/' "${SYSCTL_DROPIN}"
#fi
sysctl --system >/dev/null || true

# ===== Final ownership & sync =====
chown -R "${TARGET_USER}:${TARGET_USER}" "${PDIR}"
sync

# ===== Free port 80 for Fluidd =====
# nginx is preinstalled in the image, so Debian's default site (listen 80) is
# enabled. KIAUH reads sites-enabled to decide which ports are taken and only
# deletes "default" after the port prompt, so Fluidd on 80 is refused as
# "already in use" on the first run. Remove it before KIAUH starts.
NGINX_DEFAULT_SITE="/etc/nginx/sites-enabled/default"
if [[ -e "${NGINX_DEFAULT_SITE}" || -L "${NGINX_DEFAULT_SITE}" ]]; then
  rm -f "${NGINX_DEFAULT_SITE}"
  echo "Removed ${NGINX_DEFAULT_SITE} (frees port 80 for Fluidd)"
  if systemctl is-active --quiet nginx; then
    systemctl reload nginx || true
  fi
fi

# ===== Launch KIAUH as invoking user (optional) =====
if [[ "${RUN_KIAUH}" = "1" && -x "${KIAUH_DIR}/kiauh.sh" ]]; then
  echo "Launching KIAUH as ${TARGET_USER}..."
  sudo -u "${TARGET_USER}" "${KIAUH_DIR}/kiauh.sh"
else
  echo "KIAUH launch disabled or not found at ${KIAUH_DIR}/kiauh.sh; skipping"
fi

# ===== OpenNept4une setup (after KIAUH installed Klipper + Moonraker) =====
# Runs as the target user with -H so $HOME is theirs. Inner sudo calls reuse
# the sudo login used to start this script (asks again only after ~15 min).
ON4_SH="${TARGET_HOME}/OpenNept4une/OpenNept4une.sh"
MCU_INSTALLER="${TARGET_HOME}/OpenNept4une/img-config/rpi-mcu-install.sh"
ON4_STEPS=(install_configs usb_auto_mount install_screen_service)

print_post_kiauh_note() {
  echo "After installing Klipper, Moonraker, Fluidd (port 80) and Mainsail (port 81)"
  echo "with KIAUH (fluidd-config is already set up), run as ${TARGET_USER}:"
  for step in "${ON4_STEPS[@]}"; do
    echo "  ${ON4_SH} -y ${step}"
  done
  echo "  ${MCU_INSTALLER} \"Virtual RPi\"   (reboots when finished)"
}

if [[ "${RUN_POSTINSTALL}" != "1" ]]; then
  echo "OpenNept4une setup disabled (RUN_POSTINSTALL=${RUN_POSTINSTALL})."
  print_post_kiauh_note
elif ! systemctl cat klipper.service >/dev/null 2>&1 || ! systemctl cat moonraker.service >/dev/null 2>&1; then
  echo "Warning: Klipper and/or Moonraker are not installed; skipping OpenNept4une setup." >&2
  print_post_kiauh_note
elif [[ ! -f "${ON4_SH}" || ! -f "${MCU_INSTALLER}" ]]; then
  echo "Warning: OpenNept4une not found under ${TARGET_HOME}/OpenNept4une; skipping its setup." >&2
  print_post_kiauh_note
else
  for step in "${ON4_STEPS[@]}"; do
    echo "==> OpenNept4une: ${step}"
    sudo -u "${TARGET_USER}" -H -- bash "${ON4_SH}" -y "${step}" \
      || echo "Warning: ${step} failed; run it again from OpenNept4une.sh" >&2
  done
  echo "✅ Done. All user paths are under ${TARGET_HOME}"
  # Last: the installer reboots the printer when it finishes.
  echo "==> OpenNept4une: Virtual RPi MCU (the printer reboots when this finishes)"
  sudo -u "${TARGET_USER}" -H -- bash "${MCU_INSTALLER}" "Virtual RPi" \
    || echo "Warning: Virtual RPi MCU install failed; run update_mcu_rpi_fw from OpenNept4une.sh" >&2
  exit 0
fi

echo "✅ Done. All user paths are under ${TARGET_HOME}"
