#!/bin/bash

# 1. Exit immediately on error
set -euo pipefail

# 2. Fix the PATH for Cron (Ensures restic and rclone are found)
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# 3. Load shared configuration (includes .env finding, exports, and logging)
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
COMMON_FILE="${SCRIPT_DIR}/common.sh"

if [ -f "$COMMON_FILE" ]; then
    source "$COMMON_FILE"
else
    echo "Error: common.sh not found at constant location ${COMMON_FILE}"
    exit 1
fi

# Define Hooks Directory
HOOKS_DIR="${SCRIPT_DIR}/hooks"

# Function to run hooks
run_hooks() {
    local STAGE="$1"
    local DIR="${HOOKS_DIR}/${STAGE}-backup.d"

    if [ -d "$DIR" ]; then
        log "Running ${STAGE}-backup hooks..."
        # Iterate over executable files in the directory
        for hook in "$DIR"/*; do
            if [ -x "$hook" ]; then
                log "  -> Executing $(basename "$hook")..."
                if ! "$hook"; then
                    log "  Error: Hook $(basename "$hook") failed."
                    # We decide here if a hook failure should stop the backup.
                    # For pre-backup, yes. For post-backup, maybe not.
                    if [ "$STAGE" == "pre" ]; then
                        log "  Aborting backup due to hook failure."
                        exit 1
                    fi
                fi
            fi
        done
    else
        log "No ${STAGE}-backup hooks directory found at $DIR (skipping)"
    fi
}

log "--- OMV Backup Started ---"

# --- Step 0: Run Pre-Backup Hooks ---
run_hooks "pre"

# --- Step 1: Ensure Repository exists ---
log "Checking repository status..."
# Using --no-lock here prevents the script from hanging on stale locks during the check
if ! restic snapshots --no-lock > /dev/null 2>&1; then
    log "Repository not found. Initializing..."
    restic init
fi

# --- Step 2: Run Backup (Multi-Target) ---
# Disable exit-on-error for the loop so one failure doesn't stop others
set +e

for target in $BACKUP_TARGETS; do
    # Split "PATH:TAG" into variables
    SOURCE_PATH="${target%%:*}"
    SOURCE_TAG="${target#*:}"

    log ">>> Starting backup for: $SOURCE_PATH (Tag: $SOURCE_TAG)"

    if [ -d "$SOURCE_PATH" ]; then
        restic backup "$SOURCE_PATH" \
            --host "$(hostname)" \
            --tag "$SOURCE_TAG"

        if [ $? -ne 0 ]; then
             log "!!! Backup failed for $SOURCE_TAG"
        else
             log ">>> Backup successful for $SOURCE_TAG"
        fi
    else
        log ">>> ERROR: Path $SOURCE_PATH does not exist!"
    fi
    log "-------------------------------------------"
done

# Re-enable exit-on-error
set -e

# --- Step 3: Retention Management ---
log "Applying retention policy (forget & prune)..."
restic forget \
    --keep-last "${RETENTION_LAST}" \
    --keep-daily "${RETENTION_DAILY}" \
    --keep-weekly "${RETENTION_WEEKLY}" \
    --keep-monthly "${RETENTION_MONTHLY}" \
    --keep-yearly "${RETENTION_YEARLY}" \
    --prune

# --- Step 4: Verification ---
log "Verifying repository integrity..."
restic check

log "Current snapshots in repository:"
restic snapshots

# --- Step 5: Run Post-Backup Hooks ---
run_hooks "post"

log "--- OMV Backup Finished Successfully ---"
