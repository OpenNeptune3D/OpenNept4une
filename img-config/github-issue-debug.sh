#!/bin/bash

# Debug script for OpenNept4une/Klipper setup on Armbian SBC
# Collects git repo info, MCU versions (via Moonraker API), config files, and logs for GitHub issues

# Exit on critical errors only - we handle most errors gracefully
set -o pipefail

# Ensure we're running as the intended user, not root
if [[ $EUID -eq 0 ]]; then
    log_error "Do not run this script with sudo. Run as your normal user."
    exit 1
fi

# Explicitly set umask for user-only write, group/other read
umask 022

# =============================================================================
# Configuration
# =============================================================================

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DEBUG_DIR="/tmp/ON_debug_${TIMESTAMP}"
ZIP_DEST_DIR="$HOME/printer_data/config/debug_files"

GIT_INFO_FILE="$DEBUG_DIR/git_repos_info.txt"
MCU_INFO_FILE="$DEBUG_DIR/mcu_versions.txt"
SYSTEM_INFO_FILE="$DEBUG_DIR/system_info.txt"
MISSING_FILES_LOG="$DEBUG_DIR/missing_files.txt"

MOONRAKER_URL="http://localhost:7125"

# Sensitive patterns to redact from config files (case-insensitive grep -E pattern)
SENSITIVE_PATTERNS='(api_key|password|token|secret|credential|auth|apikey|mqtt_password|broker_password|webhook)'

# Required packages for full functionality
REQUIRED_PACKAGES=(curl jq zip)

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo "[INFO] $*" >&2
}

log_warn() {
    echo "[WARN] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

# Check if running as root (needed for package installation)
is_root() {
    [[ $EUID -eq 0 ]]
}

# Check if stdin is a terminal (interactive mode)
is_interactive() {
    [[ -t 0 ]]
}

# Get the appropriate package manager command
get_pkg_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "apt-get"
    elif command -v apt >/dev/null 2>&1; then
        echo "apt"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v yum >/dev/null 2>&1; then
        echo "yum"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    else
        echo ""
    fi
}

# Install missing packages
install_packages() {
    local packages=("$@")
    local pkg_manager
    pkg_manager=$(get_pkg_manager)

    if [[ -z "$pkg_manager" ]]; then
        log_error "No supported package manager found. Please install manually: ${packages[*]}"
        return 1
    fi

    log_info "Installing missing packages: ${packages[*]}"

    # Build command array based on root status
    local cmd=()
    if ! is_root; then
        if command -v sudo >/dev/null 2>&1; then
            cmd+=(sudo)
        else
            log_error "Not running as root and sudo not available. Please install manually: ${packages[*]}"
            return 1
        fi
    fi

    case "$pkg_manager" in
        apt-get|apt)
            "${cmd[@]}" "$pkg_manager" update -qq || return 1
            "${cmd[@]}" "$pkg_manager" install -y -qq "${packages[@]}"
            ;;
        dnf|yum)
            "${cmd[@]}" "$pkg_manager" install -y "${packages[@]}"
            ;;
        pacman)
            "${cmd[@]}" pacman -Sy --noconfirm "${packages[@]}"
            ;;
    esac
}

# Check and install dependencies
check_dependencies() {
    local missing_packages=()

    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if ! command -v "$pkg" >/dev/null 2>&1; then
            missing_packages+=("$pkg")
        fi
    done

    if [[ ${#missing_packages[@]} -eq 0 ]]; then
        log_info "All required packages are installed"
        return 0
    fi

    log_warn "Missing packages: ${missing_packages[*]}"

    # Only prompt if running interactively
    if is_interactive; then
        read -r -p "Install missing packages automatically? [y/N] " response
        case "$response" in
            [yY][eE][sS]|[yY])
                if install_packages "${missing_packages[@]}"; then
                    log_info "Packages installed successfully"
                    return 0
                else
                    log_error "Package installation failed"
                    return 1
                fi
                ;;
            *)
                log_warn "Continuing without missing packages - some features will be unavailable"
                return 0
                ;;
        esac
    else
        log_warn "Non-interactive mode: skipping package installation prompt"
        log_warn "Install manually with: sudo apt-get install ${missing_packages[*]}"
        log_warn "Continuing with reduced functionality..."
        return 0
    fi
}

# Collect git info for a repo using git -C (avoids directory changes)
collect_git_info() {
    local repo_dir="$1"
    local repo_name
    repo_name=$(basename "$repo_dir")

    if [[ ! -d "$repo_dir" ]]; then
        echo "=== $repo_name === (Directory not found: $repo_dir)" >> "$GIT_INFO_FILE"
        echo "" >> "$GIT_INFO_FILE"
        return 0
    fi

    if [[ ! -d "$repo_dir/.git" ]]; then
        echo "=== $repo_name === (Not a git repository)" >> "$GIT_INFO_FILE"
        echo "" >> "$GIT_INFO_FILE"
        return 0
    fi

    # Use git -C to avoid changing directories
    {
        echo "=== $repo_name ==="
        echo "Path: $repo_dir"
        echo "Active Branch: $(git -C "$repo_dir" branch --show-current 2>/dev/null || echo 'unknown')"
        echo "Version/Describe: $(git -C "$repo_dir" describe --tags --always --dirty 2>/dev/null || echo 'unknown')"
        echo "Last Commit: $(git -C "$repo_dir" log -1 --format='%h %s (%ci)' 2>/dev/null || echo 'unknown')"
        echo "Remote URL: $(git -C "$repo_dir" remote get-url origin 2>/dev/null || echo 'unknown')"
        echo "Status:"
        git -C "$repo_dir" status -s 2>/dev/null || echo "  (unable to get status)"
        echo ""
    } >> "$GIT_INFO_FILE"
}

# Find OpenNept4une directory (handles case variations)
find_opennept4une_dir() {
    local candidates=(
        "$HOME/OpenNept4une"
    )
    
    for dir in "${candidates[@]}"; do
        if [[ -d "$dir" ]]; then
            echo "$dir"
            return 0
        fi
    done
    
    # Not found - return empty
    echo ""
}

# Fallback function: Grep klippy.log for MCU versions
fallback_mcu_from_log() {
    local klippy_log="$HOME/printer_data/logs/klippy.log"

    if [[ -f "$klippy_log" ]]; then
        grep -E "mcu[^:]*: (git version|Version|version)" "$klippy_log" 2>/dev/null | sort -u > "$MCU_INFO_FILE"
        if [[ ! -s "$MCU_INFO_FILE" ]]; then
            echo "No MCU version information found in klippy.log" > "$MCU_INFO_FILE"
        fi
    else
        echo "klippy.log not found at $klippy_log" > "$MCU_INFO_FILE"
    fi
}

# Query MCU versions via Moonraker API
collect_mcu_versions() {
    # Check if we have the required tools
    if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
        log_warn "curl or jq not available; using log grep fallback for MCU versions"
        fallback_mcu_from_log
        return 0
    fi

    # Check if Moonraker is reachable
    if ! curl -sf --connect-timeout 5 "$MOONRAKER_URL/server/info" >/dev/null 2>&1; then
        log_warn "Moonraker API not reachable; using log grep fallback for MCU versions"
        fallback_mcu_from_log
        return 0
    fi

    # Get list of available printer objects
    local objects_response
    if ! objects_response=$(curl -sf --connect-timeout 10 "$MOONRAKER_URL/printer/objects/list" 2>/dev/null); then
        log_warn "Failed to query printer objects; using log grep fallback"
        fallback_mcu_from_log
        return 0
    fi

    # Extract MCU object names
    local mcu_objects
    mcu_objects=$(echo "$objects_response" | jq -r '.result.objects[]? | select(startswith("mcu"))' 2>/dev/null)

    if [[ -z "$mcu_objects" ]]; then
        echo "No MCU objects found in printer status" > "$MCU_INFO_FILE"
        return 0
    fi

    # Build query string for all MCUs - format: object=attr1,attr2&object2=attr1,attr2
    local query_params=""
    while IFS= read -r mcu; do
        [[ -z "$mcu" ]] && continue
        # URL-encode the MCU name (spaces become %20)
        local encoded_mcu
        encoded_mcu=$(printf '%s' "$mcu" | sed 's/ /%20/g')
        query_params="${query_params}${encoded_mcu}=mcu_version,mcu_build_versions&"
    done <<< "$mcu_objects"
    query_params="${query_params%&}"  # Remove trailing &

    # Query the versions
    local versions_response
    if versions_response=$(curl -sf --connect-timeout 10 "${MOONRAKER_URL}/printer/objects/query?${query_params}" 2>/dev/null); then
        echo "$versions_response" | jq '.result.status // empty' > "$MCU_INFO_FILE" 2>/dev/null
        if [[ ! -s "$MCU_INFO_FILE" ]]; then
            echo "No MCU version data returned from API" > "$MCU_INFO_FILE"
        fi
    else
        log_warn "Failed to query MCU versions; using log grep fallback"
        fallback_mcu_from_log
    fi
}

# Copy a file with error handling, log if missing
copy_file() {
    local src="$1"
    local dest_dir="$2"
    local optional="${3:-false}"

    if [[ -f "$src" ]]; then
        if cp -f "$src" "$dest_dir/" 2>/dev/null; then
            return 0
        else
            echo "Failed to copy: $src" >> "$MISSING_FILES_LOG"
        fi
    else
        if [[ "$optional" != "true" ]]; then
            echo "Not found: $src" >> "$MISSING_FILES_LOG"
        fi
    fi
    return 1
}

# Copy and redact sensitive information from config files
copy_config_redacted() {
    local src="$1"
    local dest_dir="$2"
    local filename
    filename=$(basename "$src")
    local dest_file="$dest_dir/$filename"

    if [[ ! -f "$src" ]]; then
        echo "Not found: $src" >> "$MISSING_FILES_LOG"
        return 1
    fi

    # Copy with sensitive fields redacted
    if sed -E "s/($SENSITIVE_PATTERNS)([[:space:]]*[:=][[:space:]]*)([^[:space:]#]+)/\1\2[REDACTED]/gi" \
        "$src" > "$dest_file" 2>/dev/null; then
        # Verify file was created and has content
        if [[ -s "$dest_file" ]]; then
            return 0
        fi
    fi
    
    echo "Failed to copy/redact: $src" >> "$MISSING_FILES_LOG"
    return 1
}

# Copy log file with optional tail for large files
copy_log_file() {
    local src="$1"
    local dest_dir="$2"
    local max_lines="${3:-0}"  # 0 means copy entire file
    local filename
    filename=$(basename "$src")

    if [[ ! -f "$src" ]]; then
        echo "Not found: $src" >> "$MISSING_FILES_LOG"
        return 1
    fi

    if [[ "$max_lines" -gt 0 ]]; then
        # Check if file is larger than threshold
        local line_count
        line_count=$(wc -l < "$src" 2>/dev/null || echo 0)
        if [[ "$line_count" -gt "$max_lines" ]]; then
            {
                echo "=== TRUNCATED: Only last $max_lines of $line_count lines included ==="
                echo ""
                tail -n "$max_lines" "$src"
            } > "$dest_dir/$filename"
            return 0
        fi
    fi

    if ! cp -f "$src" "$dest_dir/" 2>/dev/null; then
        echo "Failed to copy: $src" >> "$MISSING_FILES_LOG"
        return 1
    fi
    return 0
}

# Collect system information
collect_system_info() {
    {
        echo "=== Debug Collection Timestamp ==="
        echo "Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo ""

        echo "=== System Info ==="
        uname -a 2>/dev/null || echo "uname not available"
        echo ""
	cat /boot/.OpenNept4une.txt 2>/dev/null || echo "file not available"
	echo ""

        echo "=== OS Release ==="
        if [[ -f /etc/os-release ]]; then
            cat /etc/os-release
        elif [[ -f /etc/armbian-release ]]; then
            cat /etc/armbian-release
        else
            echo "os-release not found"
        fi
        echo ""

        echo "=== Uptime ==="
        uptime 2>/dev/null || echo "uptime not available"
        echo ""

        echo "=== Disk Usage ==="
        df -h 2>/dev/null || echo "df not available"
        echo ""

        echo "=== Memory Usage ==="
        free -h 2>/dev/null || echo "free not available"
        echo ""

        echo "=== CPU Info ==="
        if [[ -f /proc/cpuinfo ]]; then
            grep -E "^(model name|Hardware|Serial|Revision)" /proc/cpuinfo 2>/dev/null | head -10
        else
            echo "cpuinfo not available"
        fi
        echo ""

        echo "=== Temperature (if available) ==="
        local temp_found=false
        for zone in /sys/class/thermal/thermal_zone*/temp; do
            if [[ -f "$zone" ]]; then
                local zone_name zone_temp
                zone_name=$(dirname "$zone")
                zone_name=$(basename "$zone_name")
                zone_temp=$(cat "$zone" 2>/dev/null)
                if [[ -n "$zone_temp" ]]; then
                    echo "$zone_name: $((zone_temp / 1000))°C"
                    temp_found=true
                fi
            fi
        done
        if [[ "$temp_found" == "false" ]]; then
            echo "Thermal info not available"
        fi
        echo ""

        echo "=== Klipper Service Status ==="
        if command -v systemctl >/dev/null 2>&1; then
            systemctl status klipper --no-pager -l 2>&1 || echo "klipper service not found"
        else
            echo "systemctl not available"
        fi
        echo ""

        echo "=== Moonraker Service Status ==="
        if command -v systemctl >/dev/null 2>&1; then
            systemctl status moonraker --no-pager -l 2>&1 || echo "moonraker service not found"
        else
            echo "systemctl not available"
        fi
        echo ""

        echo "=== Display Connector Service Status ==="
        if command -v systemctl >/dev/null 2>&1; then
            systemctl status display --no-pager -l 2>&1 || echo "display_connector service not found"
        else
            echo "systemctl not available"
        fi
        echo ""

        echo "=== Affinity Connector Service Status ==="
        if command -v systemctl >/dev/null 2>&1; then
            systemctl status affinity --no-pager -l 2>&1 || echo "affinity service not found"
        else
            echo "systemctl not available"
        fi
        echo ""

        echo "=== USB Devices ==="
        if command -v lsusb >/dev/null 2>&1; then
            lsusb 2>/dev/null || echo "lsusb failed"
        else
            echo "lsusb not available"
        fi
        echo ""

        echo "=== Serial Devices ==="
        ls -la /dev/tty* 2>/dev/null || echo "No serial devices found in /dev/tty"
        echo ""

        echo "=== SPI Devices ==="
        ls -la /dev/spi* 2>/dev/null || echo "No serial devices found in /dev/spi"
        echo ""

        echo "=== Klipper/Moonraker Host Versions (via API) ==="
        if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
            # Query Moonraker server info for moonraker_version
            local server_info
            if server_info=$(curl -sf --connect-timeout 5 "$MOONRAKER_URL/server/info" 2>/dev/null); then
                echo "Moonraker Version: $(echo "$server_info" | jq -r '.result.moonraker_version // "unknown"')"
                echo "Klippy State: $(echo "$server_info" | jq -r '.result.klippy_state // "unknown"')"
                echo "Klippy Connected: $(echo "$server_info" | jq -r '.result.klippy_connected // "unknown"')"
            else
                echo "Moonraker API not reachable"
            fi
            
            # Query Klipper printer info for software_version (separate endpoint)
            local printer_info
            if printer_info=$(curl -sf --connect-timeout 5 "$MOONRAKER_URL/printer/info" 2>/dev/null); then
                echo "Klipper Version: $(echo "$printer_info" | jq -r '.result.software_version // "unknown"')"
                echo "Klipper Hostname: $(echo "$printer_info" | jq -r '.result.hostname // "unknown"')"
            else
                echo "Klipper printer info not available (Klippy may not be ready)"
            fi
        else
            echo "curl or jq not available for API query"
        fi
        echo ""

        echo "=== Python Version ==="
        python3 --version 2>/dev/null || python --version 2>/dev/null || echo "Python not found"
        echo ""

        echo "=== Klippy Environment ==="
        if [[ -d "$HOME/klippy-env" ]]; then
            "$HOME/klippy-env/bin/python" --version 2>/dev/null || echo "klippy-env python not accessible"
        else
            echo "klippy-env not found"
        fi

    } > "$SYSTEM_INFO_FILE"
}

# Create the final zip archive
create_archive() {
    if ! command -v zip >/dev/null 2>&1; then
        log_error "zip command not available - cannot create archive"
        log_info "Debug files are available in: $DEBUG_DIR"
        return 1
    fi

    mkdir -p "$ZIP_DEST_DIR"
    local zip_file="${ZIP_DEST_DIR}/ON_debug_${TIMESTAMP}.zip"

    # Create zip from within the debug directory (using subshell to isolate cd)
    if (cd "$DEBUG_DIR" && zip -r "$zip_file" ./* >/dev/null 2>&1); then
        rm -rf "$DEBUG_DIR"
        echo "$zip_file"
        return 0
    else
        log_error "Failed to create zip archive"
        log_info "Debug files are available in: $DEBUG_DIR"
        return 1
    fi
}

# =============================================================================
# Main Script
# =============================================================================

main() {
    log_info "OpenNept4une Debug Collection Script"
    log_info "====================================="

    # Check dependencies
    if ! check_dependencies; then
        log_error "Cannot proceed without required packages"
        exit 1
    fi

    # Create debug directory
    mkdir -p "$DEBUG_DIR"
    touch "$MISSING_FILES_LOG"

    # Collect git repository information
    log_info "Collecting git repository information..."
    touch "$GIT_INFO_FILE"
    
    # Find OpenNept4une directory (handles case variations)
    local opennept_dir
    opennept_dir=$(find_opennept4une_dir)
    if [[ -n "$opennept_dir" ]]; then
        collect_git_info "$opennept_dir"
    else
        echo "=== OpenNept4une === (Directory not found)" >> "$GIT_INFO_FILE"
        echo "" >> "$GIT_INFO_FILE"
    fi
    
    collect_git_info "$HOME/display_connector"
    collect_git_info "$HOME/klipper"
    collect_git_info "$HOME/moonraker"
    # Note: klippy-env is typically not a git repo, skip unless specifically needed

    # Collect MCU versions
    log_info "Collecting MCU versions..."
    collect_mcu_versions

    # Copy configuration files (with redaction for sensitive data)
    log_info "Copying configuration files..."
    copy_file "$HOME/printer_data/config/printer.cfg" "$DEBUG_DIR"
    copy_file "$HOME/printer_data/config/user_settings.cfg" "$DEBUG_DIR" "true" # Optional
    copy_config_redacted "$HOME/printer_data/config/moonraker.conf" "$DEBUG_DIR"
    copy_file "$HOME/printer_data/moonraker.asvc" "$DEBUG_DIR" "true"  # Optional
    copy_file "$HOME/printer_data/config/cartographer.cfg" "$DEBUG_DIR" "true" # Optional

    # Copy log files (with size limits for large logs)
    log_info "Copying log files..."
    copy_log_file "$HOME/printer_data/logs/klippy.log" "$DEBUG_DIR" 10000
    copy_log_file "$HOME/printer_data/logs/display_connector.log" "$DEBUG_DIR" 5000
    copy_log_file "$HOME/printer_data/logs/moonraker.log" "$DEBUG_DIR" 5000

    # Collect system information
    log_info "Collecting system information..."
    collect_system_info

    # Remove missing files log if empty
    if [[ ! -s "$MISSING_FILES_LOG" ]]; then
        rm -f "$MISSING_FILES_LOG"
    fi

    # Create archive
    log_info "Creating archive..."
    local zip_file
    if zip_file=$(create_archive); then
        echo ""
        log_info "====================================="
        log_info "Debug collection complete!"
        log_info "Archive created: $zip_file"
		log_info "Please download this Zip file via fluidd > Configuration Tab > debug_files > ON_debug_*_*.zip"
        log_info "Please upload the latest zip file with your GitHub issue."
        echo ""
    else
        exit 1
    fi
}

# Run main function
main "$@"
