#!/bin/bash

# Exit on error
set -euo pipefail

# Load shared configuration
# Fix PATH (similar to backup.sh)
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/homebrew/bin:$PATH"

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
COMMON_FILE="${SCRIPT_DIR}/common.sh"

if [ -f "$COMMON_FILE" ]; then
    source "$COMMON_FILE"
else
    echo "Error: common.sh not found at ${COMMON_FILE}"
    exit 1
fi

check_dependencies

restic_cmd check
restic_cmd snapshots
restic_cmd stats --mode raw-data
