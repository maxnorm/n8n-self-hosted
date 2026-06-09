#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
KEEP_DAYS=30
BACKUP_FILE="${BACKUP_DIR}/n8n_data_${TIMESTAMP}.tar.gz"

mkdir -p "$BACKUP_DIR"

echo "[$(date)] Starting n8n data volume backup..."

tar czf "$BACKUP_FILE" -C /n8n-data .

echo "[$(date)] Backup saved: $(basename "$BACKUP_FILE") ($(du -h "$BACKUP_FILE" | cut -f1))"

find "$BACKUP_DIR" -name "n8n_data_*.tar.gz" -mtime +${KEEP_DAYS} -delete
echo "[$(date)] Pruned backups older than ${KEEP_DAYS} days"
