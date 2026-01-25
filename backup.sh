#!/bin/bash

# 1. Exit immediately on error
set -euo pipefail

# 2. Fix the PATH for Cron (Ensures restic and rclone are found)
# We add /opt/homebrew/bin for Apple Silicon support and preserve existing PATH
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/homebrew/bin:$PATH"

# 3. Load shared configuration (includes .env finding, exports, and logging)
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
COMMON_FILE="${SCRIPT_DIR}/common.sh"

if [ -f "$COMMON_FILE" ]; then
    source "$COMMON_FILE"
else
    echo "Error: common.sh not found at constant location ${COMMON_FILE}"
    exit 1
fi

# Check Dependencies
check_dependencies

# Parse Arguments
DRY_RUN=false
for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            log "[DRY-RUN] Dry-run mode enabled. No changes will be made."
            ;;
    esac
done

# 4. Locking (Prevent concurrent backups)
# Uses a lockfile at /var/tmp or falls back to /tmp
LOCK_FILE="/var/tmp/restic-backup.lock"
if [ ! -d "/var/tmp" ]; then
    LOCK_FILE="/tmp/restic-backup.lock"
fi

# In Dry-Run, we might skip locking or just log it. Let's keep locking to simulate real run behavior,
# BUT if it's a dry-run we might want to allow it even if a real backup is running?
# Better safe: Enforce locking even in dry-run to test locking logic too.
exec 200>"$LOCK_FILE"
flock -n 200 || { log "Backup already running (locked by $LOCK_FILE). Aborting."; monitor_ping "fail"; exit 1; }

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
                if [ "$DRY_RUN" = true ]; then
                    log "  [DRY-RUN] Would execute $(basename "$hook")..."
                else
                    log "  -> Executing $(basename "$hook")..."
                    if ! "$hook"; then
                        log "  Error: Hook $(basename "$hook") failed."
                        if [ "$STAGE" == "pre" ]; then
                            log "  Aborting backup due to hook failure."
                            monitor_ping "fail"
                            exit 1
                        fi
                    fi
                fi
            fi
        done
    else
        log "No ${STAGE}-backup hooks directory found at $DIR (skipping)"
    fi
}

log "--- OMV Backup Started ---"

# Start Monitoring
monitor_ping "start"

# --- Step 0: Run Pre-Backup Hooks ---
run_hooks "pre"

# --- Step 1: Ensure Repository exists ---
log "Checking repository status..."
if ! restic snapshots --no-lock > /dev/null 2>&1; then
    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] Repository not found. Would initialize..."
    else
        log "Repository not found. Initializing..."
        restic init
    fi
fi

# --- Step 2: Run Backup (Multi-Target) ---
# Disable exit-on-error for the loop so one failure doesn't stop others
set +e

BACKUP_HAS_ERRORS=false

for target in $BACKUP_TARGETS; do
    # Split "PATH:TAG" into variables
    SOURCE_PATH="${target%%:*}"
    SOURCE_TAG="${target#*:}"

    log ">>> Starting backup for: $SOURCE_PATH (Tag: $SOURCE_TAG)"

    if [ -d "$SOURCE_PATH" ]; then
        if [ "$DRY_RUN" = true ]; then
             log "[DRY-RUN] Would backup $SOURCE_PATH with tag $SOURCE_TAG..."
             restic backup "$SOURCE_PATH" --host "$(hostname)" --tag "$SOURCE_TAG" --dry-run
        else
            restic backup "$SOURCE_PATH" \
                --host "$(hostname)" \
                --tag "$SOURCE_TAG"

            if [ $? -ne 0 ]; then
                 log "!!! Backup failed for $SOURCE_TAG"
                 BACKUP_HAS_ERRORS=true
            else
                 log ">>> Backup successful for $SOURCE_TAG"
            fi
        fi
    else
        log ">>> ERROR: Path $SOURCE_PATH does not exist!"
        BACKUP_HAS_ERRORS=true
    fi
    log "-------------------------------------------"
done

# Re-enable exit-on-error
set -e

# --- Step 3: Retention Management ---
log "Applying retention policy (forget & prune)..."
RESTIC_DRY_RUN_ARG=""
if [ "$DRY_RUN" = true ]; then
    RESTIC_DRY_RUN_ARG="--dry-run"
    log "[DRY-RUN] Simulating retention policy..."
fi

restic forget \
    --keep-last "${RETENTION_LAST}" \
    --keep-daily "${RETENTION_DAILY}" \
    --keep-weekly "${RETENTION_WEEKLY}" \
    --keep-monthly "${RETENTION_MONTHLY}" \
    --keep-yearly "${RETENTION_YEARLY}" \
    --prune $RESTIC_DRY_RUN_ARG

# --- Step 4: Verification ---
if [ "$DRY_RUN" = true ]; then
    log "[DRY-RUN] Skipping strict verification (check)."
else
    log "Verifying repository integrity..."
    restic check
fi

log "Current snapshots in repository:"
restic snapshots

# --- Step 5: Run Post-Backup Hooks ---
run_hooks "post"

log "--- OMV Backup Finished Successfully ---"

# Send Final Monitoring Ping
if [ "$BACKUP_HAS_ERRORS" = true ]; then
    monitor_ping "fail"
    log "Backup completed with errors."
    exit 1
else
    monitor_ping "success"
fi
