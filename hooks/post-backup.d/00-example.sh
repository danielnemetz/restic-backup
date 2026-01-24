#!/bin/bash
# Example Post-Backup Hook
# This script runs AFTER the backup finishes.
# It runs regardless of whether the backup was successful or not.

echo "Running example post-backup hook..."

# Example: Send a notification
# curl -d "Backup finished" https://ntfy.sh/my-topic

exit 0
