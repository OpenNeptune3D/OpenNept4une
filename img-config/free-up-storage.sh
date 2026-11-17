#!/usr/bin/env bash
# Safe storage cleanup for OpenNept4une / Klipper printers.
#
# Only removes things that are regenerated automatically or are pure caches:
#   - APT package cache, old journal entries, rotated/compressed logs,
#     the pip download cache, the desktop Trash and crash dumps.
# It NEVER touches printer configs, the Moonraker database, git repos,
# Python virtualenvs or installed packages.
#
# Optionally (interactive only, picked by letter and confirmed by typing
# DELETE) it can also remove the user's own files: gcodes, timelapses,
# old backups, or individual large files in the home folder.
#
# Usage: free-up-storage.sh [-n|--dry-run] [-y|--yes] [-h|--help]

set -uo pipefail

R=$'\e[1;91m'; G=$'\e[1;92m'; Y=$'\e[1;93m'; M=$'\e[1;95m'; C=$'\e[96m'; NC=$'\e[0m'

DRY_RUN="false"
AUTO_YES="false"

JOURNAL_KEEP="50M"       # journal size to keep after vacuuming
PRINTER_LOG_KEEP_DAYS=3  # keep rotated printer logs newer than this

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]
Safely free up storage space on a Klipper printer.

Options:
  -n, --dry-run   Only show how much space can be freed. Deletes nothing.
  -y, --yes       Clean every safe category without asking.
                  Your own files (gcodes, timelapses, ...) are never removed with --yes.
  -h, --help      Show this help.

Never touched: printer configs, Moonraker database, git repos,
Python environments, installed packages.
Your own files are only removed if you pick them and type DELETE.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run) DRY_RUN="true" ;;
        -y|--yes) AUTO_YES="true" ;;
        -h|--help) usage; exit 0 ;;
        *) printf '%b\n' "${R}Unknown option: $1${NC}" >&2; usage; exit 1 ;;
    esac
    shift
done

# ------------------------------------------------------------------
# Resolve the real user's home, even when started with sudo
# ------------------------------------------------------------------
if [[ -n "${SUDO_USER-}" && "${SUDO_USER}" != "root" ]]; then
    USER_NAME="$SUDO_USER"
else
    USER_NAME="$(id -un)"
fi
USER_HOME="$(getent passwd "$USER_NAME" 2>/dev/null | cut -d: -f6)"
USER_HOME="${USER_HOME:-$HOME}"

if [[ -z "$USER_HOME" || ! -d "$USER_HOME" || ( "$USER_HOME" != /home/* && "$USER_HOME" != /root ) ]]; then
    printf '%b\n' "${R}Could not resolve a sane home directory ('${USER_HOME}'). Aborting.${NC}" >&2
    exit 1
fi

if [[ "$EUID" -eq 0 ]]; then
    SUDO=""
else
    SUDO="sudo"
    printf '%b\n' "${C}Some system folders need sudo to measure and clean.${NC}"
    if ! sudo -v; then
        printf '%b\n' "${R}sudo is required. Aborting.${NC}" >&2
        exit 1
    fi
fi

# ------------------------------------------------------------------
# Refuse to run while a print is active
# ------------------------------------------------------------------
check_not_printing() {
    command -v curl >/dev/null 2>&1 || return 0
    local resp
    resp="$(curl -s --max-time 3 "http://127.0.0.1:7125/printer/objects/query?print_stats=state" 2>/dev/null)" || return 0
    if printf '%s' "$resp" | grep -Eq '"state"[[:space:]]*:[[:space:]]*"(printing|paused)"'; then
        printf '%b\n' "${R}A print is running or paused. Run this again when the printer is idle.${NC}"
        exit 1
    fi
}
check_not_printing

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------
human() {
    numfmt --to=iec --suffix=B --format='%.1f' "${1:-0}" 2>/dev/null || printf '%sB' "${1:-0}"
}

# Sum a stream of byte counts (one per line)
sum_bytes() { awk '{s+=$1} END{print s+0}'; }

dir_bytes() {
    local total=0 d b
    for d in "$@"; do
        [[ -d "$d" ]] || continue
        b="$($SUDO du -sb -- "$d" 2>/dev/null | cut -f1)"
        total=$(( total + ${b:-0} ))
    done
    printf '%s\n' "$total"
}

# Remove the CONTENTS of a directory (never the directory itself)
empty_dir() {
    local d="$1"
    [[ -n "$d" && -d "$d" && "$d" == /* && "$d" != "/" ]] || return 0
    $SUDO find "$d" -mindepth 1 -delete 2>/dev/null || true
}

# System log roots. On Armbian /var/log lives in RAM (zram) and is synced to
# /var/log.hdd on disk, so we clean both but only count the on-disk copy.
LOG_ROOTS=()
for d in /var/log /var/log.hdd; do
    [[ -d "$d" ]] && LOG_ROOTS+=("$d")
done
if [[ -d /var/log.hdd ]]; then
    DISK_LOG_ROOT=/var/log.hdd
else
    DISK_LOG_ROOT=/var/log
fi

# Run find over rotated system logs; extra args are the action (-printf/-delete)
# Usage: rotated_sys_log_find <root>... -- <action>
rotated_sys_log_find() {
    local -a roots=()
    while [[ $# -gt 0 && "$1" != "--" ]]; do roots+=("$1"); shift; done
    shift
    (( ${#roots[@]} )) || return 0
    $SUDO find "${roots[@]}" -xdev \
        -path '*/journal' -prune -o -type f \
        \( -name '*.gz' -o -name '*.xz' -o -name '*.bz2' -o -name '*.old' -o -regex '.*\.[0-9]+$' \) \
        "$@"
}

PRINTER_LOGS="$USER_HOME/printer_data/logs"

# ------------------------------------------------------------------
# Categories: label | scan (prints bytes) | clean
# ------------------------------------------------------------------
LABELS=(
    "APT package cache (downloaded .deb files)"
    "System journal (keeps newest ${JOURNAL_KEEP})"
    "Old rotated/compressed system logs"
    "Old Klipper/Moonraker logs (keeps current + last ${PRINTER_LOG_KEEP_DAYS} days)"
    "Python pip download cache"
    "Trash folder and crash dumps"
)

scan_1() { dir_bytes /var/cache/apt/archives; }
clean_1() { $SUDO apt-get clean; }

scan_2() {
    local used keep
    used="$(dir_bytes "$DISK_LOG_ROOT/journal")"
    keep="$(numfmt --from=iec "$JOURNAL_KEEP")"
    (( used > keep )) && printf '%s\n' $(( used - keep )) || printf '0\n'
}
clean_2() {
    command -v journalctl >/dev/null 2>&1 || return 0
    $SUDO journalctl --vacuum-size="$JOURNAL_KEEP" >/dev/null 2>&1
    # Armbian: also trim the on-disk copy so the space is freed now, not at next sync
    if [[ "$DISK_LOG_ROOT" != /var/log && -d "$DISK_LOG_ROOT/journal" ]]; then
        $SUDO journalctl --directory="$DISK_LOG_ROOT/journal" --vacuum-size="$JOURNAL_KEEP" >/dev/null 2>&1
    fi
    return 0
}

scan_3() { rotated_sys_log_find "$DISK_LOG_ROOT" -- -printf '%s\n' 2>/dev/null | sum_bytes; }
clean_3() { rotated_sys_log_find "${LOG_ROOTS[@]}" -- -delete 2>/dev/null || true; }

printer_log_find() {
    [[ -d "$PRINTER_LOGS" ]] || return 0
    $SUDO find "$PRINTER_LOGS" -maxdepth 1 -type f -name '*.log.*' -mtime +"$PRINTER_LOG_KEEP_DAYS" "$@"
}
scan_4() { printer_log_find -printf '%s\n' 2>/dev/null | sum_bytes; }
clean_4() { printer_log_find -delete 2>/dev/null || true; }

PIP_CACHES=("$USER_HOME/.cache/pip" /root/.cache/pip)
scan_5() { dir_bytes "${PIP_CACHES[@]}"; }
clean_5() { local d; for d in "${PIP_CACHES[@]}"; do empty_dir "$d"; done; }

JUNK_DIRS=("$USER_HOME/.local/share/Trash" /var/crash /var/lib/systemd/coredump)
scan_6() { dir_bytes "${JUNK_DIRS[@]}"; }
clean_6() { local d; for d in "${JUNK_DIRS[@]}"; do empty_dir "$d"; done; }

# ------------------------------------------------------------------
# Scan
# ------------------------------------------------------------------
root_avail() { df -B1 --output=avail / | tail -n1 | tr -d ' '; }

printf '\n%b\n' "${M}Scanning for space that can be safely freed...${NC}"
AVAIL_BEFORE="$(root_avail)"

declare -a SIZES
TOTAL=0
for i in "${!LABELS[@]}"; do
    n=$(( i + 1 ))
    SIZES[i]="$("scan_$n")"
    SIZES[i]="${SIZES[i]:-0}"
    TOTAL=$(( TOTAL + SIZES[i] ))
done

printf '\n%s\n' "=========================================================="
printf '%b\n' "  ${C}Safe cleanup${NC}  |  Free space now: ${G}$(human "$AVAIL_BEFORE")${NC}"
printf '%s\n' "=========================================================="
for i in "${!LABELS[@]}"; do
    printf ' %d) %-9s %s\n' $(( i + 1 )) "$(human "${SIZES[i]}")" "${LABELS[i]}"
done
printf '%s\n' "----------------------------------------------------------"
printf '%b\n' "    ${G}$(human "$TOTAL")${NC}  total that can be freed"

# ------------------------------------------------------------------
# Optional: the user's own files. Only removed when picked by letter
# AND confirmed by typing DELETE. Never removed with --yes.
# ------------------------------------------------------------------
GCODE_DIR="$USER_HOME/printer_data/gcodes"
GCODE_OLD_DAYS=30
LARGE_FILE_MIN="50M"
LARGE_FILE_MAX_LIST=20
TIMELAPSE_DIRS=("$USER_HOME/timelapse" "$USER_HOME/printer_data/timelapse")
BACKUP_DIRS=("$USER_HOME/kiauh_backups" "$USER_HOME/printer_data/backup")
MOONRAKER_URL="http://127.0.0.1:7125"

# Gcode files (NUL-separated). Skips the USB stick mount and thumbnail folders.
# Extra args (e.g. -mtime +30) are added as filters.
gcode_files() {
    [[ -d "$GCODE_DIR" ]] || return 0
    find "$GCODE_DIR" -xdev -mindepth 1 \( -path "$GCODE_DIR/USB" -o -name '.thumbs' \) -prune -o \
        -type f \( -iname '*.gcode' -o -iname '*.gco' -o -iname '*.g' -o -iname '*.bgcode' -o -iname '*.ufp' \) \
        "$@" -print0 2>/dev/null
}

files_in_dirs() {
    local d
    for d in "$@"; do
        [[ -d "$d" ]] && find "$d" -xdev -type f -print0 2>/dev/null
    done
    return 0
}

# Large files in home as "bytes<TAB>path", biggest first. Skips installed software
# (git repos, Python envs), hidden app folders (~/.claude, ~/.vscode-server, ...),
# the Moonraker database and the categories above.
large_files() {
    local size path
    find "$USER_HOME" -xdev \
        \( -name .git -o -name '*-env' -o -name node_modules \
           -o -path "$USER_HOME/.*" -o -path "$GCODE_DIR" -o -path "$USER_HOME/printer_data/database" \
           -o -path "$USER_HOME/timelapse" -o -path "$USER_HOME/printer_data/timelapse" \
           -o -path "$USER_HOME/kiauh_backups" -o -path "$USER_HOME/printer_data/backup" \) -prune -o \
        -type f -size +"$LARGE_FILE_MIN" -printf '%s\t%p\n' 2>/dev/null \
        | sort -rn \
        | while IFS=$'\t' read -r size path; do
            # Anything inside a git checkout belongs to installed software: skip it
            git -C "$(dirname "$path")" rev-parse --is-inside-work-tree >/dev/null 2>&1 && continue
            printf '%s\t%s\n' "$size" "$path"
        done \
        | head -n "$LARGE_FILE_MAX_LIST"
}

files_bytes() {
    (( $# )) || { printf '0\n'; return; }
    stat -c %s -- "$@" 2>/dev/null | sum_bytes
}

short_path() { printf '%s' "${1/#"$USER_HOME"/\~}"; }

printf '\n%b\n' "${M}Looking for your own large files...${NC}"
mapfile -d '' GCODE_ALL < <(gcode_files)
mapfile -d '' GCODE_OLD < <(gcode_files -mtime +"$GCODE_OLD_DAYS")
mapfile -d '' TIMELAPSE_FILES < <(files_in_dirs "${TIMELAPSE_DIRS[@]}")
mapfile -d '' BACKUP_FILES < <(files_in_dirs "${BACKUP_DIRS[@]}")
LARGE_SIZES=(); LARGE_PATHS=()
while IFS=$'\t' read -r size path; do
    [[ -n "$path" ]] || continue
    LARGE_SIZES+=("$size"); LARGE_PATHS+=("$path")
done < <(large_files)

declare -A USER_OPT_OK=()
show_user_opt() {  # letter, count, bytes, label
    (( $2 > 0 )) || return 0
    USER_OPT_OK[$1]=1
    local word="files"
    (( $2 == 1 )) && word="file"
    printf ' %b) %-9s %s (%d %s)\n' "${Y}$1${NC}" "$(human "$3")" "$4" "$2" "$word"
}

printf '\n%b\n' "${Y}Your files${NC} (only removed if you pick them AND type DELETE):"
show_user_opt G "${#GCODE_ALL[@]}" "$(files_bytes "${GCODE_ALL[@]}")" "All gcode files, USB stick skipped"
show_user_opt O "${#GCODE_OLD[@]}" "$(files_bytes "${GCODE_OLD[@]}")" "Gcode files older than ${GCODE_OLD_DAYS} days"
show_user_opt T "${#TIMELAPSE_FILES[@]}" "$(files_bytes "${TIMELAPSE_FILES[@]}")" "Timelapse videos and frames"
show_user_opt B "${#BACKUP_FILES[@]}" "$(files_bytes "${BACKUP_FILES[@]}")" "Old KIAUH / Moonraker backups"
LARGE_TOTAL=0
for s in "${LARGE_SIZES[@]}"; do LARGE_TOTAL=$(( LARGE_TOTAL + s )); done
show_user_opt L "${#LARGE_PATHS[@]}" "$LARGE_TOTAL" "Other files over ${LARGE_FILE_MIN}B, pick one by one"
(( ${#USER_OPT_OK[@]} )) || printf '    (nothing found)\n'
printf '%s\n' "=========================================================="

if [[ "$DRY_RUN" == "true" ]]; then
    if (( ${#LARGE_PATHS[@]} )); then
        printf '\n%b\n' "${Y}Files over ${LARGE_FILE_MIN}B:${NC}"
        for i in "${!LARGE_PATHS[@]}"; do
            printf '    %-9s %s\n' "$(human "${LARGE_SIZES[i]}")" "$(short_path "${LARGE_PATHS[i]}")"
        done
    fi
    printf '\n%b\n' "${Y}Dry run: nothing was deleted.${NC}"
    exit 0
fi

# ------------------------------------------------------------------
# Choose: safe categories
# ------------------------------------------------------------------
SELECTED=()
if (( TOTAL == 0 )); then
    printf '\n%b\n' "${G}Safe cleanup: nothing to clean.${NC}"
elif [[ "$AUTO_YES" == "true" ]]; then
    for i in "${!LABELS[@]}"; do SELECTED+=( $(( i + 1 )) ); done
else
    printf '\n%b' "${G}Safe cleanup: ${NC}[${G}A${NC}]ll, numbers like ${C}1 3 5${NC}, [${Y}N${NC}]one, or [${R}Q${NC}]uit: "
    read -r answer
    case "$answer" in
        a|A|"") for i in "${!LABELS[@]}"; do SELECTED+=( $(( i + 1 )) ); done ;;
        n|N) ;;
        q|Q) printf '%b\n' "${Y}Cancelled. Nothing was deleted.${NC}"; exit 0 ;;
        *)
            for tok in ${answer//,/ }; do
                if [[ "$tok" =~ ^[0-9]+$ ]] && (( tok >= 1 && tok <= ${#LABELS[@]} )); then
                    SELECTED+=( "$tok" )
                else
                    printf '%b\n' "${R}Ignoring invalid choice: ${tok}${NC}"
                fi
            done
            ;;
    esac
fi

# ------------------------------------------------------------------
# Choose: the user's own files (interactive only)
# ------------------------------------------------------------------
declare -A DEL_SET=()
DEL_FILES=()
add_del() {
    local f
    for f in "$@"; do
        [[ -n "$f" && -z "${DEL_SET[$f]-}" ]] || continue
        DEL_SET[$f]=1
        DEL_FILES+=("$f")
    done
}

pick_large_files() {
    local i tok
    printf '\n%b\n' "${Y}Files over ${LARGE_FILE_MIN}B:${NC}"
    for i in "${!LARGE_PATHS[@]}"; do
        printf ' %2d) %-9s %s\n' $(( i + 1 )) "$(human "${LARGE_SIZES[i]}")" "$(short_path "${LARGE_PATHS[i]}")"
    done
    printf '%b' "${G}Pick numbers like ${C}1 3${G}, [${NC}A${G}]ll, or Enter for none:${NC} "
    read -r tok_line
    case "$tok_line" in
        "") return 0 ;;
        a|A) add_del "${LARGE_PATHS[@]}"; return 0 ;;
    esac
    for tok in ${tok_line//,/ }; do
        if [[ "$tok" =~ ^[0-9]+$ ]] && (( tok >= 1 && tok <= ${#LARGE_PATHS[@]} )); then
            add_del "${LARGE_PATHS[tok-1]}"
        else
            printf '%b\n' "${R}Ignoring invalid choice: ${tok}${NC}"
        fi
    done
}

if [[ "$AUTO_YES" != "true" ]] && (( ${#USER_OPT_OK[@]} )); then
    printf '\n%b' "${G}Also remove your own files? Letters like ${Y}G T${G}, or Enter to skip:${NC} "
    read -r answer
    answer="${answer^^}"
    for (( c = 0; c < ${#answer}; c++ )); do
        letter="${answer:c:1}"
        [[ "$letter" == [[:space:],] ]] && continue
        if [[ -z "${USER_OPT_OK[$letter]-}" ]]; then
            printf '%b\n' "${R}Ignoring invalid choice: ${letter}${NC}"
            continue
        fi
        case "$letter" in
            G) add_del "${GCODE_ALL[@]}" ;;
            O) add_del "${GCODE_OLD[@]}" ;;
            T) add_del "${TIMELAPSE_FILES[@]}" ;;
            B) add_del "${BACKUP_FILES[@]}" ;;
            L) pick_large_files ;;
        esac
    done

    if (( ${#DEL_FILES[@]} )); then
        printf '\n%b\n' "${R}About to PERMANENTLY delete ${#DEL_FILES[@]} file(s), $(human "$(files_bytes "${DEL_FILES[@]}")"):${NC}"
        for i in "${!DEL_FILES[@]}"; do
            (( i < 10 )) || { printf '    ... and %d more\n' $(( ${#DEL_FILES[@]} - 10 )); break; }
            printf '    %s\n' "$(short_path "${DEL_FILES[i]}")"
        done
        printf '%b' "${R}Type DELETE to confirm${NC} (anything else keeps them): "
        read -r confirm
        if [[ "$confirm" != "DELETE" ]]; then
            printf '%b\n' "${G}Kept your files.${NC}"
            DEL_FILES=()
        fi
    fi
fi

if (( ${#SELECTED[@]} == 0 && ${#DEL_FILES[@]} == 0 )); then
    printf '\n%b\n' "${Y}Nothing selected. Nothing was deleted.${NC}"
    exit 0
fi

# ------------------------------------------------------------------
# Clean
# ------------------------------------------------------------------
printf '\n'
for n in "${SELECTED[@]}"; do
    printf '%b' "  Cleaning: ${LABELS[n-1]} ... "
    if "clean_$n"; then
        printf '%b\n' "${G}done${NC}"
    else
        printf '%b\n' "${Y}skipped (error)${NC}"
    fi
done

# Gcodes go through Moonraker when it is running, so its file list,
# thumbnails and metadata stay in sync. Otherwise plain rm.
delete_gcode_via_moonraker() {
    local rel="${1#"$GCODE_DIR"/}" enc code
    enc="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$rel")" || return 1
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -X DELETE "$MOONRAKER_URL/server/files/gcodes/$enc")"
    [[ "$code" == 2* ]]
}

if (( ${#DEL_FILES[@]} )); then
    use_api="false"
    if command -v curl >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 \
        && curl -s --max-time 3 "$MOONRAKER_URL/server/info" >/dev/null 2>&1; then
        use_api="true"
    fi
    removed=0; failed=0
    printf '%b' "  Deleting your selected files ... "
    for f in "${DEL_FILES[@]}"; do
        [[ -f "$f" ]] || continue
        if [[ "$use_api" == "true" && "$f" == "$GCODE_DIR"/* ]] && delete_gcode_via_moonraker "$f"; then
            removed=$(( removed + 1 ))
        elif rm -f -- "$f" 2>/dev/null && [[ ! -e "$f" ]]; then
            removed=$(( removed + 1 ))
        else
            failed=$(( failed + 1 ))
        fi
    done
    if (( failed )); then
        printf '%b\n' "${Y}${removed} removed, ${failed} could not be removed${NC}"
    else
        printf '%b\n' "${G}${removed} removed${NC}"
    fi
fi

sync
AVAIL_AFTER="$(root_avail)"
FREED=$(( AVAIL_AFTER - AVAIL_BEFORE ))
(( FREED < 0 )) && FREED=0

printf '\n%s\n' "=========================================================="
printf '%b\n' "  ${G}Freed $(human "$FREED")${NC} on /   |   Free space now: ${G}$(human "$AVAIL_AFTER")${NC}"
printf '%s\n' "=========================================================="
