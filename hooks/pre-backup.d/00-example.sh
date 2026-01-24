#!/bin/bash
# Example Pre-Backup Hook
# This script runs BEFORE the backup starts.
# If it fails (non-zero exit code), the backup will be ABORTED.

echo "Running example pre-backup hook..."

# Example: Export a docker container database
# docker exec my-db-container pg_dump -U user dbname > /path/to/backup/dump.sql

exit 0
