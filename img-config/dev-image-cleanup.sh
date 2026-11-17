#!/usr/bin/env bash
# dev-image-cleanup.sh: prepare THIS printer's eMMC for imaging and release.
#
# DESTRUCTIVE. Removes everything personal or unique to this machine
# (Wi-Fi, SSH host keys, machine-id, Moonraker database, gcodes, logs,
# shell history, git/gh credentials, Claude Code, dev-only packages),
# expands the root partition and powers off. Image the eMMC after that.
#
# Usage: dev-image-cleanup.sh [-n|--dry-run] [-y|--yes] [--no-poweroff]
#        [--keep-dev-tools] [--keep-claude] [-h|--help]

set -euo pipefail
shopt -s nullglob dotglob

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; NC='\033[0m'

DRY_RUN="false"
AUTO_YES="false"
POWEROFF="true"
KEEP_DEV_TOOLS="false"
KEEP_CLAUDE="false"

# Installed by hand while developing. Checked on 2026-11-17: not called by
# klipper, moonraker, fluidd, mainsail, mobileraker, kiauh, OpenNept4une,
# display_connector, display_firmware, katapult or cartographer.
# (OpenNept4une only has "# shellcheck" comments, which need no binary.)
# cmake/g++ stay: webcam-setup.sh needs them. python3-pip stays: installers use it.
DEV_PACKAGES=(gh shellcheck strace)

# Repos to put back on their default branch before imaging.
RELEASE_REPOS=(display_connector OpenNept4une)

# Printer services stopped before their data is wiped.
PRINTER_SERVICES=(display mobileraker moonraker klipper klipper-mcu mjpg-streamer-webcam1)

# Top-level entries expected in the user's home on a release image.
# Anything else is listed at the end (not removed) so you can check it.
EXPECTED_HOME=(
  .bash_aliases .bash_logout .bashrc .profile .config .local .cache
  printer_data klipper klippy-env moonraker moonraker-env fluidd fluidd-config
  mainsail kiauh OpenNept4une display_connector display_firmware
  mobileraker_companion mobileraker-env Klipper-Adaptive-Meshing-Purging
  katapult cartographer3d-plugin cartographer_firmware mjpg-streamer
)

usage() {
  cat <<'EOF'
Prepare this printer for imaging and release. DESTRUCTIVE, then powers off.

Usage: dev-image-cleanup.sh [options]
  -n, --dry-run      Print every command instead of running it.
  -y, --yes          Do not ask for confirmation (headless).
      --no-poweroff  Stay on at the end (printer services are restarted).
                     New SSH logins fail until the next boot (host keys removed).
      --keep-dev-tools  Do not purge dev-only packages (gh, shellcheck, strace).
      --keep-claude  Do not remove Claude Code (~/.claude and friends).
  -h, --help         Show this help.
EOF
}

ORIG_ARGS=("$@")
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run) DRY_RUN="true" ;;
    -y|--yes) AUTO_YES="true" ;;
    --no-poweroff) POWEROFF="false" ;;
    --keep-dev-tools) KEEP_DEV_TOOLS="true" ;;
    --keep-claude) KEEP_CLAUDE="true" ;;
    -h|--help) usage; exit 0 ;;
    *) printf '%b\n' "${R}Unknown option: $1${NC}" >&2; usage; exit 1 ;;
  esac
  shift
done

# Everything below runs as root; user-owned git work runs as the real user.
if [[ "$EUID" -ne 0 ]]; then
  exec sudo -- "$0" "${ORIG_ARGS[@]}"
fi

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------
step() { printf '\n%b\n' "${C}== $* ==${NC}"; }
info() { printf '   %s\n' "$*"; }
warn() { printf '%b\n' "   ${Y}$*${NC}"; }
die()  { printf '%b\n' "${R}ERROR: $*${NC}" >&2; exit 1; }

# run CMD...: execute, or only print it with --dry-run.
run() {
  if [[ "$DRY_RUN" == "true" ]]; then
    printf '   [dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

# Remove paths that exist; never fails the script.
REMOVED=()
remove() {
  local p
  for p in "$@"; do
    [[ -e "$p" || -L "$p" ]] || continue
    REMOVED+=("$p")
    run rm -rf -- "$p" || warn "Could not remove $p"
  done
}

as_user() { sudo -u "$USER_NAME" -H -- "$@"; }

# ------------------------------------------------------------------
# Resolve the real user
# ------------------------------------------------------------------
USER_NAME="${SUDO_USER:-}"
[[ -n "$USER_NAME" && "$USER_NAME" != "root" ]] \
  || die "Run as your normal user (it re-runs itself with sudo), not as root."
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
[[ -n "$USER_HOME" && -d "$USER_HOME" && "$USER_HOME" == /home/* ]] \
  || die "Home for '$USER_NAME' is '$USER_HOME', which is unexpected. Aborting."
PDATA="$USER_HOME/printer_data"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ------------------------------------------------------------------
# Preflight: nothing destructive happens before this passes
# ------------------------------------------------------------------
step "Preflight"

if command -v curl >/dev/null 2>&1; then
  state="$(curl -s --max-time 3 "http://127.0.0.1:7125/printer/objects/query?print_stats=state" 2>/dev/null || true)"
  if printf '%s' "$state" | grep -Eq '"state"[[:space:]]*:[[:space:]]*"(printing|paused)"'; then
    die "A print is running or paused."
  fi
fi

# Uncommitted work would otherwise end up in the release image.
dirty=()
for r in "${RELEASE_REPOS[@]}"; do
  repo="$USER_HOME/$r"
  as_user git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1 || continue
  [[ -z "$(as_user git -C "$repo" status --porcelain 2>/dev/null)" ]] || dirty+=("$repo")
done
if (( ${#dirty[@]} )); then
  for r in "${dirty[@]}"; do warn "Uncommitted changes in $r"; done
  [[ "$DRY_RUN" == "true" ]] || die "Commit or stash the changes above first."
fi

# Host keys are deleted below and must be recreated on the user's first boot.
# Debian's sshd-keygen.service does that when /etc/machine-id is empty.
systemctl cat sshd-keygen.service >/dev/null 2>&1 \
  || die "sshd-keygen.service not found: SSH host keys would not be recreated on first boot."

info "User: $USER_NAME ($USER_HOME)"
[[ "$DRY_RUN" == "true" ]] && info "Dry run: nothing will be changed."

if [[ "$AUTO_YES" != "true" && "$DRY_RUN" != "true" ]]; then
  printf '\n%b\n' "${R}This wipes personal data, Wi-Fi, SSH host keys, the Moonraker database,"
  printf '%b\n' "gcodes and logs on THIS printer, then powers it off.${NC}"
  printf '%b' "Type ${R}RELEASE${NC} to continue: "
  read -r answer
  [[ "$answer" == "RELEASE" ]] || { printf '%b\n' "${G}Cancelled. Nothing changed.${NC}"; exit 0; }
fi

# ------------------------------------------------------------------
# 1) Repos back on the default branch
# ------------------------------------------------------------------
step "1/10 Update release repos"
update_repo() {
  local repo="$1" remote branch
  if ! as_user git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    info "Skipping $repo (not a git repo)"; return 0
  fi
  remote="origin"
  as_user git -C "$repo" remote get-url "$remote" >/dev/null 2>&1 \
    || remote="$(as_user git -C "$repo" remote | head -n1)"
  [[ -n "$remote" ]] || { info "Skipping $repo (no remote)"; return 0; }
  run as_user git -C "$repo" fetch --prune "$remote" \
    || { warn "Fetch failed for $repo (offline?)"; return 0; }
  branch="$(as_user git -C "$repo" symbolic-ref --short "refs/remotes/$remote/HEAD" 2>/dev/null || true)"
  branch="${branch#"$remote"/}"; branch="${branch:-main}"
  if as_user git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
    run as_user git -C "$repo" checkout "$branch" || { warn "Checkout failed in $repo"; return 0; }
  else
    run as_user git -C "$repo" checkout -b "$branch" --track "$remote/$branch" \
      || { warn "No $remote/$branch in $repo"; return 0; }
  fi
  run as_user git -C "$repo" pull --ff-only "$remote" "$branch" \
    || warn "Pull failed in $repo (local commits?)"
  info "$repo -> $branch"
}
for r in "${RELEASE_REPOS[@]}"; do update_repo "$USER_HOME/$r"; done

# ------------------------------------------------------------------
# 2) Safe cleanup (apt cache, journal, rotated logs, pip cache, coredumps)
# ------------------------------------------------------------------
step "2/10 Safe storage cleanup (free-up-storage.sh --yes)"
FREE_STORAGE="$SCRIPT_DIR/free-up-storage.sh"
if [[ -x "$FREE_STORAGE" ]]; then
  if [[ "$DRY_RUN" == "true" ]]; then
    SUDO_USER="$USER_NAME" bash "$FREE_STORAGE" --dry-run || true
  else
    SUDO_USER="$USER_NAME" bash "$FREE_STORAGE" --yes || warn "free-up-storage.sh failed; continuing"
  fi
else
  warn "$FREE_STORAGE not found; skipping"
fi

# ------------------------------------------------------------------
# 3) Stop printer services so they don't rewrite what we delete
# ------------------------------------------------------------------
step "3/10 Stop printer services"
for s in "${PRINTER_SERVICES[@]}"; do
  systemctl cat "$s.service" >/dev/null 2>&1 || continue
  run systemctl stop "$s.service" || warn "Could not stop $s"
done

# ------------------------------------------------------------------
# 4) Printer data
# ------------------------------------------------------------------
step "4/10 Printer data"
# printer.cfg is created per model by set-printer-model.sh on first setup.
remove "$PDATA/config/printer.cfg"
[[ -f "$PDATA/config/user_settings.cfg" ]] && run truncate -s 0 "$PDATA/config/user_settings.cfg"
remove "$PDATA/gcodes/"* "$PDATA/logs/"* "$PDATA/timelapse" "$PDATA/backup" \
       "$PDATA/comms/"* "$USER_HOME/kiauh_backups"

# Moonraker database: holds the API key, print history, Mobileraker push
# tokens and webcam/UI settings. Reset to the OpenNept4une default; Moonraker
# converts data.mdb into a fresh moonraker-sql.db on its next start.
DEFAULT_DB="$USER_HOME/OpenNept4une/img-config/printer-data/data.mdb"
if [[ -f "$DEFAULT_DB" ]]; then
  remove "$PDATA/database/"*
  run install -o "$USER_NAME" -g "$USER_NAME" -m 0644 "$DEFAULT_DB" "$PDATA/database/data.mdb"
  info "Moonraker database reset to the OpenNept4une default"
else
  warn "$DEFAULT_DB missing; Moonraker database NOT reset"
fi
# Unique per install; Moonraker writes a new one on start.
remove "$PDATA/.moonraker.uuid"

# Printer model line: set again by set-printer-model.sh on first setup.
for f in /boot/.OpenNept4une.txt /boot/.OpenNept4une.cfg; do
  [[ -f "$f" ]] || continue
  if grep -qi '^n4' "$f"; then
    info "Removing model line from $f: $(grep -i '^n4' "$f" | head -n1)"
    run sed -i '/^n4/I d' "$f"
  fi
  remove "$f.bak"
done

# ------------------------------------------------------------------
# 5) Personal files, credentials, Claude Code
# ------------------------------------------------------------------
step "5/10 Personal files and credentials"
for h in "$USER_HOME" /root; do
  remove "$h/.bash_history" "$h/.python_history" "$h/.lesshst" "$h/.wget-hsts" \
         "$h/.viminfo" "$h/.sudo_as_admin_successful" "$h/.Xauthority" \
         "$h/.gitconfig" "$h/.git-credentials" "$h/.config/gh" \
         "$h/.ssh/authorized_keys" "$h/.ssh/known_hosts" "$h/.ssh/known_hosts.old" \
         "$h/.cache/"* "$h/.local/share/Trash" "$h/.local/share/nano"
done
remove /var/run/sudo/ts/*

if [[ "$KEEP_CLAUDE" != "true" ]]; then
  for h in "$USER_HOME" /root; do
    remove "$h/.claude" "$h/.claude.json" "$h/.claude.json.backup" \
           "$h/.local/share/claude" "$h/.local/state/claude" "$h/.local/bin/claude"
  done
  info "Claude Code removed"
fi
# Empty dirs left behind by the above
[[ -d "$USER_HOME/.local/bin" ]] && run rmdir --ignore-fail-on-non-empty "$USER_HOME/.local/bin"

# ------------------------------------------------------------------
# 6) Dev-only packages
# ------------------------------------------------------------------
step "6/10 Dev-only packages"
if [[ "$KEEP_DEV_TOOLS" == "true" ]]; then
  info "Kept (--keep-dev-tools)"
else
  purge=()
  for p in "${DEV_PACKAGES[@]}"; do
    dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "install ok installed" || continue
    # Skip a package if purging it would take any other package with it.
    others="$(apt-get -s purge "$p" 2>/dev/null | awk '/^Purg |^Remv /{print $2}' | grep -vx "$p" || true)"
    if [[ -n "$others" ]]; then
      warn "Keeping $p: purging it would also remove $(echo "$others" | tr '\n' ' ')"
      continue
    fi
    purge+=("$p")
  done
  if (( ${#purge[@]} )); then
    run env DEBIAN_FRONTEND=noninteractive apt-get purge -y "${purge[@]}" || warn "Purge failed"
    info "Purged: ${purge[*]}"
  else
    info "None installed"
  fi
  # gh's own apt repo, if it was added the official way
  remove /etc/apt/sources.list.d/github-cli.list /etc/apt/sources.list.d/github-cli.sources \
         /etc/apt/keyrings/githubcli-archive-keyring.gpg /usr/share/keyrings/githubcli-archive-keyring.gpg
fi
run env DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y || warn "autoremove failed"
run apt-get clean || true
remove /var/lib/apt/lists/* /var/cache/apt/*.bin

# ------------------------------------------------------------------
# 7) Network
# ------------------------------------------------------------------
step "7/10 Network (Wi-Fi, leases)"
remove /etc/NetworkManager/system-connections/* /etc/resolv.conf.backup \
       /var/lib/NetworkManager/*.lease /var/lib/NetworkManager/seen-bssids \
       /var/lib/NetworkManager/timestamps /var/lib/NetworkManager/secret_key \
       /var/lib/dhcp/* /var/lib/dhcpcd/* /var/lib/dhcpcd5/* \
       /var/lib/systemd/network/*.lease /var/lib/systemd/resolved/*

# ------------------------------------------------------------------
# 8) Machine identity
# ------------------------------------------------------------------
step "8/10 Machine identity"
# Empty (not missing) machine-id = "first boot" for systemd: it writes a new
# ID, and sshd-keygen.service (ConditionFirstBoot=yes) creates new host keys.
# Do NOT run ssh-keygen -A here, or every image would share the same keys.
run truncate -s 0 /etc/machine-id
[[ -L /var/lib/dbus/machine-id ]] || remove /var/lib/dbus/machine-id
remove /etc/ssh/ssh_host_* /var/lib/systemd/random-seed /var/lib/systemd/credential.secret
run systemctl enable sshd-keygen.service >/dev/null 2>&1 || true

# ------------------------------------------------------------------
# 9) Temp files, logs, caches
# ------------------------------------------------------------------
step "9/10 Temp files and logs"
remove /var/crash/* /var/lib/systemd/coredump/*
# Leave the private dirs and sockets of services that are still running.
for t in /tmp/* /var/tmp/*; do
  case "${t##*/}" in systemd-private-*|.*-unix) continue ;; esac
  remove "$t"
done
run journalctl --rotate >/dev/null 2>&1 || true
run journalctl --vacuum-time=1s >/dev/null 2>&1 || true
# Armbian keeps /var/log in RAM and copies it to /var/log.hdd at shutdown:
# clean both. Rotated files are deleted, current ones emptied.
for d in /var/log /var/log.hdd; do
  [[ -d "$d" ]] || continue
  [[ -d "$d/journal" ]] && run find "$d/journal" -mindepth 1 -delete
  if [[ "$DRY_RUN" == "true" ]]; then
    info "[dry-run] empty all files and delete rotated logs under $d"
  else
    find "$d" -type f \( -name '*.gz' -o -name '*.xz' -o -name '*.old' -o -regex '.*\.[0-9]+' \) -delete 2>/dev/null || true
    find "$d" -type f -exec truncate -s 0 {} + 2>/dev/null || true
  fi
done
if [[ "$DRY_RUN" == "true" ]]; then
  info "[dry-run] delete __pycache__ under /usr/lib/python3 and $USER_HOME"
else
  find /usr/lib/python3 "$USER_HOME" -xdev -type d -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null || true
fi

# ------------------------------------------------------------------
# 10) Expand root to the full eMMC, trim free space
# ------------------------------------------------------------------
step "10/10 Root partition"
DEV="/dev/mmcblk1"; PART="${DEV}p2"
if [[ "$(findmnt -no SOURCE /)" == "$PART" && -b "$DEV" ]]; then
  if [[ "$DRY_RUN" == "true" ]]; then
    info "[dry-run] grow $PART to the end of $DEV, then resize2fs"
  else
    echo ',+' | sfdisk --force --no-reread -N 2 "$DEV" || warn "sfdisk failed"
    partprobe "$DEV" || true
    resize2fs "$PART" || warn "resize2fs failed"
  fi
else
  info "Root is not on $PART; skipping expand"
fi
# Unused blocks read back as zeros on most eMMC: smaller compressed image.
run fstrim -v / || true

# ------------------------------------------------------------------
# Report anything unexpected left in the home folder
# ------------------------------------------------------------------
unexpected=()
for e in "$USER_HOME"/*; do
  name="${e##*/}"
  [[ " ${EXPECTED_HOME[*]} " == *" $name "* ]] && continue
  [[ " ${REMOVED[*]} " == *" $e "* ]] && continue
  unexpected+=("$name")
done
if (( ${#unexpected[@]} )); then
  step "Check these (not removed)"
  for n in "${unexpected[@]}"; do warn "$USER_HOME/$n"; done
fi

if [[ "$DRY_RUN" == "true" ]]; then
  step "Dry run finished. Nothing was changed."
  exit 0
fi

sync
if [[ "$POWEROFF" == "true" ]]; then
  if (( ${#unexpected[@]} )) && [[ "$AUTO_YES" != "true" ]]; then
    printf '\n%b' "Power off now? Unexpected files above stay in the image. [y/N] "
    read -r answer
    [[ "$answer" == [yY]* ]] || { printf '%b\n' "${Y}Not powering off. Remove them, then: sudo poweroff${NC}"; exit 0; }
  fi
  step "Done. Powering off: image the eMMC now."
  sleep 2; sync
  poweroff
else
  for s in "${PRINTER_SERVICES[@]}"; do
    systemctl cat "$s.service" >/dev/null 2>&1 && systemctl start "$s.service" || true
  done
  step "Done. Not powered off (--no-poweroff). Power off before imaging."
fi
