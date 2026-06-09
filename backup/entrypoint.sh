#!/usr/bin/env bash
set -euo pipefail

echo "[$(date)] Starting backup scheduler..."

/app/backup-db.sh >> /var/log/backup.log 2>&1 || true
/app/backup-n8n-data.sh >> /var/log/backup.log 2>&1 || true

echo "[$(date)] Initial backup complete. Starting cron..."
exec crond -f -l 2
