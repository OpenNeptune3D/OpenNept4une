#!/usr/bin/env bash
# file: /usr/local/sbin/setup-usb-automount.sh
# Installs a udev rule to auto-mount USB partitions at a fixed path using systemd-mount.
# Why: short-lived RUN+= actions, FS-specific options, optional idle unmount, safe defaults.

set -euo pipefail

# ===== Config (override via env) =====
USER_NAME="${USER_NAME:-mks}"
MOUNT_POINT="${MOUNT_POINT:-/home/mks/printer_data/gcodes/USB}"
RULE_PATH="${RULE_PATH:-/etc/udev/rules.d/99-usb_automount.rules}"
EXTRA_OPTS="${EXTRA_OPTS:-}"                      # Only for FAT-like (e.g., "flush,async")
IDLE_TIMEOUT_SEC="${IDLE_TIMEOUT_SEC:-0}"         # 0 = disabled
HARDEN_OPTS="${HARDEN_OPTS:-nodev,nosuid,noexec}" # Drop noexec if you must run binaries

# ===== Helpers =====
die() { echo "Error: $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

# ===== Pre-flight =====
need_cmd id
need_cmd udevadm
need_cmd systemd-mount

SYSMOUNT_BIN="$(command -v systemd-mount)"
[[ -x "$SYSMOUNT_BIN" ]] || die "systemd-mount not found"

id -u "$USER_NAME" >/dev/null 2>&1 || die "User '$USER_NAME' does not exist"
uid="$(id -u "$USER_NAME")"
gid="$(id -g "$USER_NAME")"

[[ "$MOUNT_POINT" = *" "* ]] && die "MOUNT_POINT must not contain spaces"

# Normalize comma-lists (avoid stray spaces breaking options)
EXTRA_OPTS="${EXTRA_OPTS//[[:space:]]/}"
HARDEN_OPTS="${HARDEN_OPTS//[[:space:]]/}"

# Validate timeout input
[[ "${IDLE_TIMEOUT_SEC}" =~ ^[0-9]+$ ]] || die "IDLE_TIMEOUT_SEC must be an integer >= 0"

# Ensure mountpoint exists and ownership is correct
sudo mkdir -p "$MOUNT_POINT" || die "mkdir $MOUNT_POINT"
sudo chown "$USER_NAME:$USER_NAME" "$MOUNT_POINT" || die "chown $MOUNT_POINT"

# Remove any existing rule
sudo rm -f "$RULE_PATH"

# ===== Build mount options =====
base_hardening="${HARDEN_OPTS:+,${HARDEN_OPTS}}"
fatlike_opts="uid=${uid},gid=${gid},noatime${base_hardening}${EXTRA_OPTS:+,${EXTRA_OPTS}}"
posix_opts="noatime${base_hardening}"  # uid/gid ignored on POSIX fs

# Detect --timeout-idle-sec support
timeout_supported=0
if "$SYSMOUNT_BIN" --help 2>&1 | grep -q -- '--timeout-idle-sec'; then
  timeout_supported=1
fi
timeout_arg=""
if (( timeout_supported && IDLE_TIMEOUT_SEC > 0 )); then
  timeout_arg="--timeout-idle-sec=${IDLE_TIMEOUT_SEC}"
fi

# ===== Write udev rules (no pipes in RUN+=) =====
sudo tee "$RULE_PATH" >/dev/null <<RULES
# Automount a single USB filesystem to a fixed path for user ${USER_NAME}

# FAT-like filesystems (uid/gid effective)
ACTION=="add", SUBSYSTEM=="block", ENV{ID_BUS}=="usb", ENV{DEVTYPE}=="partition", ENV{ID_FS_USAGE}=="filesystem", ENV{ID_FS_TYPE}=="vfat",    RUN+="${SYSMOUNT_BIN} --no-block ${timeout_arg} --collect --options=${fatlike_opts} %E{DEVNAME} ${MOUNT_POINT}"
ACTION=="add", SUBSYSTEM=="block", ENV{ID_BUS}=="usb", ENV{DEVTYPE}=="partition", ENV{ID_FS_USAGE}=="filesystem", ENV{ID_FS_TYPE}=="exfat",   RUN+="${SYSMOUNT_BIN} --no-block ${timeout_arg} --collect --options=${fatlike_opts} %E{DEVNAME} ${MOUNT_POINT}"
ACTION=="add", SUBSYSTEM=="block", ENV{ID_BUS}=="usb", ENV{DEVTYPE}=="partition", ENV{ID_FS_USAGE}=="filesystem", ENV{ID_FS_TYPE}=="ntfs",    RUN+="${SYSMOUNT_BIN} --no-block ${timeout_arg} --collect --options=${fatlike_opts} %E{DEVNAME} ${MOUNT_POINT}"
ACTION=="add", SUBSYSTEM=="block", ENV{ID_BUS}=="usb", ENV{DEVTYPE}=="partition", ENV{ID_FS_USAGE}=="filesystem", ENV{ID_FS_TYPE}=="ntfs-3g", RUN+="${SYSMOUNT_BIN} --no-block ${timeout_arg} --collect --options=${fatlike_opts} %E{DEVNAME} ${MOUNT_POINT}"

# POSIX filesystems (ownership from FS)
ACTION=="add", SUBSYSTEM=="block", ENV{ID_BUS}=="usb", ENV{DEVTYPE}=="partition", ENV{ID_FS_USAGE}=="filesystem", ENV{ID_FS_TYPE}!="vfat", ENV{ID_FS_TYPE}!="exfat", ENV{ID_FS_TYPE}!="ntfs", ENV{ID_FS_TYPE}!="ntfs-3g", RUN+="${SYSMOUNT_BIN} --no-block --automount=yes ${timeout_arg} --collect --options=${posix_opts} %E{DEVNAME} ${MOUNT_POINT}"

# Unmount on removal
ACTION=="remove", SUBSYSTEM=="block", ENV{ID_BUS}=="usb", RUN+="${SYSMOUNT_BIN} --no-block --umount ${MOUNT_POINT}"
RULES

# Permissions on rule file
sudo chmod 0644 "$RULE_PATH"

# ===== Activate =====
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=block --action=add

# ===== Summary =====
echo "✅ Installed udev automount rule: $RULE_PATH"
echo "   Mount point: $MOUNT_POINT (owner ${USER_NAME}:${USER_NAME})"
echo "   FAT-like options: ${fatlike_opts}"
echo "   POSIX fs options: ${posix_opts}"
if (( timeout_supported )); then
  if (( IDLE_TIMEOUT_SEC > 0 )); then
    echo "   Idle auto-unmount: ${IDLE_TIMEOUT_SEC}s (enabled)"
  else
    echo "   Idle auto-unmount: disabled (0s)"
  fi
else
  echo "   Idle auto-unmount: unsupported by $(basename "$SYSMOUNT_BIN")"
fi
