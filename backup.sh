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

# Check Permissions
check_permissions

# Configure File Logging
# Try /var/log, fall back to /tmp/restic-backup.log if not writable
LOG_FILE="/var/log/restic-backup.log"
if ! touch "$LOG_FILE" 2>/dev/null; then
    LOG_FILE="/tmp/restic-backup.log"
    if ! touch "$LOG_FILE" 2>/dev/null; then
        echo "Warning: Cannot write to log files /var/log or /tmp. File logging disabled." >&2
        LOG_FILE=""
    fi
fi
if [ -n "$LOG_FILE" ]; then
    log "Logging to: $LOG_FILE"
fi

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
TOTAL_FILES_NEW=0
TOTAL_FILES_CHANGED=0
TOTAL_BYTES=0
TOTAL_DURATION=0

for target in $BACKUP_TARGETS; do
    # Split "PATH:TAG" into variables
    SOURCE_PATH="${target%%:*}"
    SOURCE_TAG="${target#*:}"

    log ">>> Starting backup for: $SOURCE_PATH (Tag: $SOURCE_TAG)"

    if [ -d "$SOURCE_PATH" ]; then
        
        # Temp file for JSON output
        JSON_OUT="/tmp/restic_out_${SOURCE_TAG//[^a-zA-Z0-9]/_}.json"
        
        if [ "$DRY_RUN" = true ]; then
             log "[DRY-RUN] Would backup $SOURCE_PATH with tag $SOURCE_TAG..."
             restic backup "$SOURCE_PATH" --host "$(hostname)" --tag "$SOURCE_TAG" --dry-run --json > "$JSON_OUT"
        else
            restic backup "$SOURCE_PATH" \
                --host "$(hostname)" \
                --tag "$SOURCE_TAG" \
                --json > "$JSON_OUT"
        fi
        
        EXIT_CODE=$?

        # Parse JSON output (last line contains summary)
        if [ -s "$JSON_OUT" ]; then
            # Extract summary object from the last line (using tail -n1 because restic streams progress)
            SUMMARY=$(tail -n1 "$JSON_OUT") 
            
            # Check if it's valid JSON
            if echo "$SUMMARY" | jq -e . >/dev/null 2>&1; then
                # Extract Stats
                FILES_NEW=$(echo "$SUMMARY" | jq '.files_new // 0')
                FILES_CHANGED=$(echo "$SUMMARY" | jq '.files_changed // 0')
                BYTES=$(echo "$SUMMARY" | jq '.total_bytes_processed // 0')
                DURATION=$(echo "$SUMMARY" | jq '.total_duration // 0')
                
                # Accumulate
                TOTAL_FILES_NEW=$((TOTAL_FILES_NEW + FILES_NEW))
                TOTAL_FILES_CHANGED=$((TOTAL_FILES_CHANGED + FILES_CHANGED))
                TOTAL_BYTES=$((TOTAL_BYTES + BYTES))
                TOTAL_DURATION=$(echo "$TOTAL_DURATION + $DURATION" | bc 2>/dev/null || echo "$TOTAL_DURATION") # float math via bc needed? restic gives seconds
                
                log "    Stats: New: $FILES_NEW, Changed: $FILES_CHANGED, Bytes: $(numfmt --to=iec-i --suffix=B $BYTES)"
            else
                 # Fallback if JSON is weird (e.g. fatal error immediately, output isn't JSON)
                 log "    Warning: Could not parse Restic JSON output."
            fi
            
            # Cleanup
            rm -f "$JSON_OUT"
        fi

        if [ $EXIT_CODE -ne 0 ]; then
             log "!!! Backup failed for $SOURCE_TAG"
             BACKUP_HAS_ERRORS=true
        else
             log ">>> Backup successful for $SOURCE_TAG"
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
    # Construct Payload
    PAYLOAD=$(jq -n \
                  --arg files_new "$TOTAL_FILES_NEW" \
                  --arg files_changed "$TOTAL_FILES_CHANGED" \
                  --arg bytes "$TOTAL_BYTES" \
                  '{files_new: $files_new, files_changed: $files_changed, total_bytes: $bytes}')
    
    monitor_ping "success" "$PAYLOAD"
fi
