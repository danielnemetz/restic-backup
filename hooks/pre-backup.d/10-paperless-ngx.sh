#!/bin/bash

# Pre-backup hook for Paperless NGX
# Exports documents to /mnt/usr/apps/paperless-ngx/export

# 1. Exit on error
set -euo pipefail

# 2. Run Export
echo "--- Hook: Paperless NGX Export Started ---"
docker exec ix-paperless-ngx-webserver-1 document_exporter /usr/src/paperless/export -d -f > /dev/null
echo "--- Hook: Paperless NGX Export Finished ---"
