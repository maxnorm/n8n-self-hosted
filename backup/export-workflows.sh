#!/usr/bin/env bash
set -euo pipefail

N8N_HOST="${N8N_HOST:-n8n}"
N8N_PORT="${N8N_PORT:-5678}"
N8N_API="http://${N8N_HOST}:${N8N_PORT}"
OUTPUT_DIR="/workflows"
API_KEY_FILE="${N8N_API_KEY_FILE:-/n8n-data/.api-key}"

if [ ! -f "$API_KEY_FILE" ] || [ ! -s "$API_KEY_FILE" ]; then
  echo "[$(date)] ERROR: API key file not found at ${API_KEY_FILE}"
  exit 1
fi

N8N_API_KEY=$(cat "$API_KEY_FILE" | tr -d '\n')

echo "[$(date)] Exporting workflows from n8n API..."

WORKFLOWS=$(curl -sf -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
  "${N8N_API}/api/v1/workflows?limit=500")

if [ -z "$WORKFLOWS" ] || [ "$WORKFLOWS" = "null" ]; then
  echo "[$(date)] ERROR: Failed to fetch workflow list"
  exit 1
fi

COUNT=$(echo "$WORKFLOWS" | jq '.data | length')
echo "[$(date)] Found ${COUNT} workflows"

echo "$WORKFLOWS" | jq -r '.data[].id' | while read -r WF_ID; do
  WF_DATA=$(curl -sf -H "X-N8N-API-KEY: ${N8N_API_KEY}" \
    "${N8N_API}/api/v1/workflows/${WF_ID}")

  if [ -n "$WF_DATA" ] && [ "$WF_DATA" != "null" ]; then
    WF_NAME=$(echo "$WF_DATA" | jq -r '.name // "unknown"' | tr ' /' '_')
    echo "$WF_DATA" | jq '.' > "${OUTPUT_DIR}/${WF_ID}.json"
    echo "[$(date)] Exported: ${WF_NAME} (${WF_ID})"
  else
    echo "[$(date)] WARNING: Failed to export workflow ${WF_ID}"
  fi
done

echo "[$(date)] Workflows exported to ${OUTPUT_DIR}"
ls -1 "${OUTPUT_DIR}"/*.json 2>/dev/null || echo "[$(date)] No workflow files found"
