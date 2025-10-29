#!/bin/bash
# file: opennept4une-setup.sh
# Purpose: Prepare Armbian host for Klipper/Fluidd using sudo (not root $HOME)

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
apt-get -y dist-upgrade
apt-get -y autoremove
apt-get autoclean
apt-get clean

# ===== Groups and udev for gpio/spi =====
if ! getent group gpio >/dev/null; then groupadd gpio; fi
usermod -a -G gpio "${TARGET_USER}"
GPIO_RULE='/etc/udev/rules.d/99-gpio.rules'
if [[ ! -f "${GPIO_RULE}" ]]; then
  printf 'SUBSYSTEM=="gpio", KERNEL=="gpiochip*", GROUP="gpio", MODE="0660"\n' | tee "${GPIO_RULE}" >/dev/null
fi

if ! getent group spiusers >/dev/null; then groupadd spiusers; fi
usermod -a -G spiusers "${TARGET_USER}"

# ===== spidev fix files (best-effort) =====
ROCKCHIP_DIR="/boot/dtb/rockchip/overlay"
mkdir -p "${ROCKCHIP_DIR}"
if [[ -f "${SPIDEV_SRC_DIR}/99-spidev.rules" ]]; then
  cp "${SPIDEV_SRC_DIR}/99-spidev.rules" /etc/udev/rules.d/
else
  echo "WARN: ${SPIDEV_SRC_DIR}/99-spidev.rules not found; skipping"
fi
for f in rockchip-fixup.scr rockchip-spi-spidev.dtbo; do
  if [[ -f "${SPIDEV_SRC_DIR}/${f}" ]]; then
    cp "${SPIDEV_SRC_DIR}/${f}" "${ROCKCHIP_DIR}/"
  else
    echo "WARN: ${SPIDEV_SRC_DIR}/${f} not found; skipping"
  fi
done

udevadm control --reload-rules || true
udevadm trigger --subsystem-match=gpio --action=add || true

# ===== Cron: periodic sync (root crontab) =====
CRON_ENTRY='*/10 * * * * /bin/sync'
( crontab -l 2>/dev/null | grep -q '/bin/sync' ) || { (crontab -l 2>/dev/null; echo "${CRON_ENTRY}") | crontab -; echo "Added cron sync every 10m"; }

# ===== Kernel RT budget =====
SYSCTL_DROPIN="/etc/sysctl.d/10-disable-rt-group-limit.conf"
if ! grep -qs '^kernel\.sched_rt_runtime_us' "${SYSCTL_DROPIN}" 2>/dev/null; then
  printf 'kernel.sched_rt_runtime_us = -1\n' | tee "${SYSCTL_DROPIN}" >/dev/null
else
  sed -i 's/^kernel\.sched_rt_runtime_us.*/kernel.sched_rt_runtime_us = -1/' "${SYSCTL_DROPIN}"
fi
sysctl --system >/dev/null || true

# ===== Final ownership & sync =====
chown -R "${TARGET_USER}:${TARGET_USER}" "${PDIR}"
sync

# ===== Launch KIAUH as invoking user =====
if [[ -x "${KIAUH_DIR}/kiauh.sh" ]]; then
  echo "Launching KIAUH as ${TARGET_USER}..."
  sudo -u "${TARGET_USER}" "${KIAUH_DIR}/kiauh.sh"
else
  echo "KIAUH not found/executable at ${KIAUH_DIR}/kiauh.sh; skipping"
fi

echo "✅ Done. All user paths are under ${TARGET_HOME}"
