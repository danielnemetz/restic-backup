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
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}
