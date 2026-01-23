#!/bin/bash

# Exit on error
set -euo pipefail

# Load shared configuration
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
COMMON_FILE="${SCRIPT_DIR}/common.sh"

if [ -f "$COMMON_FILE" ]; then
    source "$COMMON_FILE"
else
    echo "Error: common.sh not found at ${COMMON_FILE}"
    exit 1
fi

restic check
restic snapshots
