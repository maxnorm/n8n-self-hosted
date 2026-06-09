#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
KEEP_DAYS=30
BACKUP_FILE="${BACKUP_DIR}/n8n_db_${TIMESTAMP}.sql.gz"

mkdir -p "$BACKUP_DIR"

echo "[$(date)] Starting database backup..."

pg_dump -h postgres -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
  | gzip > "$BACKUP_FILE"

echo "[$(date)] Backup saved: $(basename "$BACKUP_FILE") ($(du -h "$BACKUP_FILE" | cut -f1))"

find "$BACKUP_DIR" -name "n8n_db_*.sql.gz" -mtime +${KEEP_DAYS} -delete
echo "[$(date)] Pruned backups older than ${KEEP_DAYS} days"
