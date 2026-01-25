#!/bin/bash

# Shared configuration and helper functions for Restic Backup scripts

# 1. Exit immediately on error (if not already set, but good practice to have here too for functions)
# However, sourcing scripts usually inherit flags, but let's be safe without being intrusive.
# We won't force 'set -e' here to avoid breaking sourcing scripts if they handle errors differently,
# but we recommend it in the parent scripts.

# 2. Robust path to the .env file
# This finds the directory where the SCRIPT ITSELF is located, resolving symlinks
SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
ENV_FILE="${SCRIPT_DIR}/.env"

if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    echo "Error: .env file not found at $ENV_FILE" >&2
    exit 1
fi

# 3. Export environment variables for restic
# These must be defined in .env
if [ -z "${RESTIC_REPOSITORY:-}" ] || [ -z "${RESTIC_PASSWORD:-}" ] || [ -z "${RCLONE_CONFIG:-}" ]; then
    echo "Error: Required environment variables (RESTIC_REPOSITORY, RESTIC_PASSWORD, RCLONE_CONFIG) are missing in .env" >&2
    exit 1
fi

export RESTIC_REPOSITORY
export RESTIC_PASSWORD
export RCLONE_CONFIG

# 4. Logging Helper
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg"
    # Append to log file if variable is set and file is writable (or creatable)
    if [ -n "${LOG_FILE:-}" ]; then
        echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

# 5. Permission Check
check_permissions() {
    # Check if .env is too open (Group/Other read/write/exec)
    # Using stat to get octal permissions.
    # macOS/BSD 'stat -f %A' vs GNU 'stat -c %a'
    local perms
    if stat -f %A "$ENV_FILE" > /dev/null 2>&1; then
        # macOS / BSD
        perms=$(stat -f %Lp "$ENV_FILE")
    else
        # GNU / Linux
        perms=$(stat -c %a "$ENV_FILE")
    fi

    # Check if last two digits are "00" (e.g., 600, 400).
    # If not 00, it means group or others have some access.
    if [[ "$perms" != *00 ]]; then
        log "WARNING: Insecure permissions ($perms) on $ENV_FILE. Should be 600."
        log "Fix with: chmod 600 $ENV_FILE"
        # We don't exit here, just warn.
    fi
}

# 6. Dependency Check
check_dependencies() {
    local missing=0
    for cmd in restic rclone flock; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "Error: Required command '$cmd' not found." >&2
            missing=1
        fi
    done

    if [ $missing -eq 1 ]; then
        echo "Please install missing dependencies." >&2
        exit 1
    fi
}

# 6. Monitoring (Healthchecks.io / Uptime Kuma)
monitor_ping() {
    local status="$1" # start, success, fail
    if [ -n "${HEALTHCHECK_URL:-}" ]; then
        # If url ends with /, remove it
        local url="${HEALTHCHECK_URL%/}"
        
        # Check if curl exists (dependency check should catch this but let's be safe)
        if command -v curl &> /dev/null; then
             log "Result: Sending monitoring ping ($status)..."
             # Use a timeout so we don't hang forever on a ping
             curl -fsS -m 10 --retry 3 "${url}/${status}" > /dev/null || log "Warning: Monitoring ping failed."
        fi
    fi
}
