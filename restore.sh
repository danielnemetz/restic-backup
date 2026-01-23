#!/bin/bash

# Exit on error
set -eu

# Load shared configuration
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
COMMON_FILE="${SCRIPT_DIR}/common.sh"

if [ -f "$COMMON_FILE" ]; then
    source "$COMMON_FILE"
else
    echo "Error: common.sh not found at ${COMMON_FILE}"
    exit 1
fi

# --- Step 1: Fetch snapshots and present a menu ---
echo "Fetching available snapshots from Google Drive..."
echo "------------------------------------------------------------"

# We get the snapshots in a format: ID  Date  Hostname  Tags  Paths
# Using 'mapfile' to read the list of snapshots into an array
mapfile -t SNAPSHOTS < <(restic snapshots --no-lock | grep -E '^[0-9a-f]{8}')

if [ ${#SNAPSHOTS[@]} -eq 0 ]; then
    echo "No snapshots found in repository."
    exit 1
fi

# Display the snapshots with an index
for i in "${!SNAPSHOTS[@]}"; do
    printf "[%2d] %s\n" "$i" "${SNAPSHOTS[$i]}"
done

echo "------------------------------------------------------------"
echo -n "Select the number of the snapshot to restore [0-$(( ${#SNAPSHOTS[@]} - 1 ))]: "
read -r INDEX

# Validate input
if [[ ! "$INDEX" =~ ^[0-9]+$ ]] || [ "$INDEX" -ge "${#SNAPSHOTS[@]}" ]; then
    echo "Invalid selection. Aborting."
    exit 1
fi

# Extract the ID (first 8 characters) from the selected line
SELECTED_SNAPSHOT_ID=$(echo "${SNAPSHOTS[$INDEX]}" | awk '{print $1}')

# --- Step 2: Define Restore Target ---
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Determine the default suggestion based on environment variable or current dir
DEFAULT_BASE="${MAILCOW_BACKUP_LOCATION:-.}"
DEFAULT_TARGET="${DEFAULT_BASE}_restore_${TIMESTAMP}"

echo "------------------------------------------------------------"
echo "Where should the backup be restored?"
echo "You can edit the path below. Press TAB for auto-completion."

# -e enables readline (TAB completion)
# -i pre-fills the input with the default target
# -p displays the prompt text
read -e -i "${DEFAULT_TARGET}" -p "Destination Path: " FINAL_RESTORE_DIR

# Security check: If user cleared the line and hit enter, restore default
if [ -z "${FINAL_RESTORE_DIR}" ]; then
    FINAL_RESTORE_DIR="${DEFAULT_TARGET}"
fi

echo "Selected Snapshot ID: $SELECTED_SNAPSHOT_ID"

# Check if directory exists, create if necessary
if [ ! -d "$FINAL_RESTORE_DIR" ]; then
    echo "Creating restore directory: ${FINAL_RESTORE_DIR}"
    mkdir -p "${FINAL_RESTORE_DIR}"
else
    echo "Restoring to existing directory: ${FINAL_RESTORE_DIR}"
fi

# --- Step 3: Run Restic Restore ---
echo "Restoring data... this may take a while."
restic restore "$SELECTED_SNAPSHOT_ID" --target "$FINAL_RESTORE_DIR"

echo "----------------------------------------------------------"
echo "SUCCESS: Data restored to:"
echo "${FINAL_RESTORE_DIR}"
echo "----------------------------------------------------------"
