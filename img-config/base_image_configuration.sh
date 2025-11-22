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
FLUIDD_DB_URL="${FLUIDD_DB_URL:-https://raw.githubusercontent.com/OpenNeptune3D/OpenNept4une/main/img-config/printer-data/data.mdb}"
ARM_ENV_PATH="${ARM_ENV_PATH:-/boot/armbianEnv.txt}"
RUN_KIAUH="${RUN_KIAUH:-1}"
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
DB_PATH="${PDB_DIR}/data.mdb"

echo "==> TARGET_USER=${TARGET_USER}"
echo "==> TARGET_HOME=${TARGET_HOME}"

# ===== Load rk805 PMIC driver at boot (for enabling mainboard power LEDs) =====
printf "pinctrl-rk805\n" | tee /etc/modules-load.d/rk805.conf >/dev/null

# ===== Netplan -> NetworkManager (simple & safer) =====
if [[ -f "$NETPLAN_FILE" ]] && command -v netplan >/dev/null 2>&1; then
  # Ensure NetworkManager is present/enabled before switching renderer.
  if systemctl list-unit-files | grep -q '^NetworkManager\.service'; then
    systemctl enable --now NetworkManager.service
  else
    echo "Warning: NetworkManager.service not found; skipping netplan renderer switch" >&2
  fi

  if grep -qE '^\s*renderer:\s*networkd\s*$' "$NETPLAN_FILE"; then
    sed -i 's/^\(\s*renderer:\s*\)networkd\s*$/\1NetworkManager/' "$NETPLAN_FILE"
    echo "Updated renderer to NetworkManager in $NETPLAN_FILE"
  else
    echo "No renderer: networkd line found (or already NetworkManager); leaving $NETPLAN_FILE unchanged"
  fi

  netplan generate
  netplan apply

  systemctl disable --now systemd-networkd.service systemd-networkd.socket systemd-networkd-wait-online.service NetworkManager-wait-online.service || true
  systemctl mask systemd-networkd-wait-online.service || true
else
  echo "Warning: netplan not available or $NETPLAN_FILE not found; skipping netplan/network changes" >&2
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
touch "${ARM_ENV_PATH}"
if grep -q '^extraargs=' "${ARM_ENV_PATH}"; then
  if ! grep -q '^extraargs=.*\bnet\.ifnames=0\b' "${ARM_ENV_PATH}"; then
    sed -i 's/^extraargs=\(.*\)$/extraargs=\1 net.ifnames=0/' "${ARM_ENV_PATH}"
    echo "Updated ${ARM_ENV_PATH} (added net.ifnames=0)"
  else
    echo "extraargs already contains net.ifnames=0"
  fi
else
  printf 'extraargs=net.ifnames=0\n' >> "${ARM_ENV_PATH}"
  echo "Added extraargs=net.ifnames=0 to ${ARM_ENV_PATH}"
fi

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

# ===== Launch KIAUH as invoking user (optional) =====
if [[ "${RUN_KIAUH}" = "1" && -x "${KIAUH_DIR}/kiauh.sh" ]]; then
  echo "Launching KIAUH as ${TARGET_USER}..."
  sudo -u "${TARGET_USER}" "${KIAUH_DIR}/kiauh.sh"
else
  echo "KIAUH launch disabled or not found at ${KIAUH_DIR}/kiauh.sh; skipping"
fi

echo "✅ Done. All user paths are under ${TARGET_HOME}"
