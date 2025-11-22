#!/usr/bin/env bash
# Armbian image cleanup + sanitize + prep-for-release

set -euo pipefail
shopt -s nullglob dotglob

echo "== Starting cleanup for redistribution =="

# ------------------------------------
# Resolve invoking user's home (sudo-safe)
# ------------------------------------
if [[ ${SUDO_USER-} && ${SUDO_USER} != "root" ]]; then
  USER_NAME="${SUDO_USER}"
else
  USER_NAME="$(id -un)"
fi

if command -v getent >/dev/null 2>&1; then
  USER_HOME="$(getent passwd "$USER_NAME" | awk -F: '{print $6}')"
else
  USER_HOME="$(eval "echo ~${USER_NAME}")"
fi

if [[ -z "${USER_HOME}" || ! -d "${USER_HOME}" ]]; then
  echo "ERROR: Could not resolve home for '${USER_NAME}'. Aborting." >&2
  exit 1
fi

# Extra safety: refuse to rm if USER_HOME looks wrong
if [[ "$USER_HOME" != /home/* && "$USER_HOME" != /root ]]; then
  echo "ERROR: USER_HOME='$USER_HOME' is unexpected. Aborting for safety." >&2
  exit 1
fi

# Use sudo only when not already root
if [[ "${EUID}" -eq 0 ]]; then
  SUDO=""
else
  SUDO="sudo"
fi

# ------------------------------------
# 1) Reset Git repos to latest default branch (main/master)
# ------------------------------------
reset_repo_to_default_branch() {
  local repo="$1"

  if [[ ! -d "$repo" ]]; then
    echo "   Skipping $repo (dir missing)"
    return 0
  fi

  if git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "-- Hard resetting repo: $repo --"

    local remote="origin"
    if ! git -C "$repo" remote get-url origin >/dev/null 2>&1; then
      remote="$(git -C "$repo" remote 2>/dev/null | head -n1 || true)"
    fi
    if [[ -z "$remote" ]]; then
      echo "   No remote found, skipping fetch/reset."
      return 0
    fi

    if ! git -C "$repo" fetch --prune "$remote"; then
      echo "   Fetch failed (offline?). Skipping reset for $repo"
      return 0
    fi

    local branch=""
    branch="$(git -C "$repo" symbolic-ref --quiet --short "refs/remotes/$remote/HEAD" 2>/dev/null \
              | sed "s#^$remote/##")"

    if [[ -z "$branch" ]]; then
      if git -C "$repo" show-ref --verify --quiet "refs/remotes/$remote/main"; then
        branch="main"
      elif git -C "$repo" show-ref --verify --quiet "refs/remotes/$remote/master"; then
        branch="master"
      else
        echo "   Can't determine default branch on $remote, skipping."
        return 0
      fi
    fi

    if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
      git -C "$repo" checkout "$branch"
    else
      git -C "$repo" checkout -B "$branch" "$remote/$branch"
    fi

    git -C "$repo" reset --hard "$remote/$branch"
    git -C "$repo" clean -fdx

    if [[ -f "$repo/.gitmodules" ]]; then
      git -C "$repo" submodule sync --recursive
      git -C "$repo" submodule update --init --recursive --force
    fi
  else
    echo "   Skipping $repo (not a git repo)"
  fi
}

reset_repo_to_default_branch "$USER_HOME/display_connector"
reset_repo_to_default_branch "$USER_HOME/OpenNept4une"

# -----------------------------
# 2) Personalised files cleanup
# -----------------------------
echo "-- Removing personal/app-specific files --"

rm -f "$USER_HOME/printer_data/configs/printer.cfg" || true

# Remove N4* model line from OpenNept4une file (txt or cfg), keep backup
for OPENNEP_FILE in /boot/.OpenNept4une.txt /boot/.OpenNept4une.cfg; do
  if $SUDO test -f "$OPENNEP_FILE"; then
    echo "-- Sanitizing $OPENNEP_FILE (removing N4* model line) --"
    $SUDO cp -a "$OPENNEP_FILE" "${OPENNEP_FILE}.bak"
    $SUDO sed -i '/^N4.*/d' "$OPENNEP_FILE"
  fi
done

# Remove contents (globs unquoted; nullglob on)
$SUDO rm -rf "$USER_HOME/printer_data/logs/"* || true
rm -rf "$USER_HOME/printer_data/gcodes/"* || true

# Shell histories
$SUDO rm -f /root/.bash_history || true
rm -f "$USER_HOME/.bash_history" || true

# Extra user caches/traces
$SUDO rm -rf /root/.cache/* "$USER_HOME/.cache/"* 2>/dev/null || true
rm -rf "$USER_HOME/.local/share/Trash/"* 2>/dev/null || true
$SUDO rm -f /var/run/sudo/ts/* 2>/dev/null || true

# ------------------------------------
# 3) Network / DNS sanitizing
# ------------------------------------
echo "-- Clearing network config and leases --"

$SUDO rm -rf /etc/NetworkManager/system-connections/* || true
$SUDO rm -f /etc/resolv.conf.backup || true

$SUDO rm -f /var/lib/NetworkManager/*.lease 2>/dev/null || true
$SUDO rm -f /var/lib/dhcp/* 2>/dev/null || true
$SUDO rm -f /var/lib/dhcpcd5/* 2>/dev/null || true
$SUDO rm -f /var/lib/systemd/network/*.lease 2>/dev/null || true
$SUDO rm -f /var/lib/systemd/resolved/* 2>/dev/null || true

# ------------------------------------
# 4) Regenerate-unique identity on boot
# ------------------------------------
echo "-- Removing machine identity and SSH host keys --"

$SUDO rm -f /etc/machine-id /var/lib/dbus/machine-id || true

$SUDO rm -f /etc/ssh/ssh_host_* || true
$SUDO ssh-keygen -A

# ------------------------------------
# 5) Free space/package cleanup
# ------------------------------------
echo "-- Cleaning apt caches and removing unused packages --"

$SUDO apt clean || true
$SUDO apt autoclean || true
$SUDO apt autoremove --purge -y || true

$SUDO rm -rf /var/lib/apt/lists/* || true
$SUDO rm -rf /var/cache/apt/archives/* || true

$SUDO rm -rf /tmp/* /var/tmp/* || true

echo "-- Clearing logs/journals --"
$SUDO journalctl --rotate --vacuum-time=1s || true
$SUDO rm -rf /var/log/journal/* || true
$SUDO find /var/log -type f -name "*.gz" -delete || true
$SUDO find /var/log -type f -name "*.old" -delete || true

echo "-- Removing __pycache__ --"
$SUDO find /usr/lib/python3 "$USER_HOME" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true

# ------------------------------------
# 6) Expand root partition (only if expected layout)
# ------------------------------------
echo "-- Expanding root partition if /dev/mmcblk1p2 exists --"
DEV="/dev/mmcblk1"
PART="${DEV}p2"

if [[ -b "$DEV" && -b "$PART" ]]; then
  echo ',+' | $SUDO sfdisk --force -N 2 "$DEV"
  $SUDO partprobe "$DEV" || true
  $SUDO resize2fs "$PART"
else
  echo "   Skipping partition expand: $DEV or $PART not found."
fi

# ------------------------------------
# Done
# ------------------------------------
echo "== Cleanup complete. Syncing and powering off. =="

sync
sleep 2
sync
$SUDO poweroff
