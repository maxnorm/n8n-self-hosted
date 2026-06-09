#!/usr/bin/env bash
# Pull all workflows from the running n8n instance into ./workflows via API
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOWS_DIR="${WORKFLOWS_DIR:-$ROOT_DIR/workflows}"

cd "$ROOT_DIR"

# Load .env if present
if [ -f "$ROOT_DIR/.env" ]; then
  set -a
  source "$ROOT_DIR/.env"
  set +a
fi

N8N_HOST="${N8N_HOST:-localhost}"
N8N_PORT="${N8N_PORT:-5678}"
N8N_API="http://${N8N_HOST}:${N8N_PORT}"

# Try to read API key from .env, then from the n8n_data volume
if [ -n "${N8N_API_KEY:-}" ]; then
  API_KEY="$N8N_API_KEY"
else
  API_KEY=$(docker run --rm -v n8n_test_n8n_data:/n8n-data alpine cat /n8n-data/.api-key 2>/dev/null || true)
fi

if [ -z "$API_KEY" ]; then
  echo "Error: No API key found." >&2
  echo "Either set N8N_API_KEY in .env or ensure the auto-seeded key exists in n8n_data volume." >&2
  exit 1
fi

# Check n8n is reachable
if ! curl -sf "${N8N_API}/healthz" > /dev/null 2>&1; then
  echo "Error: n8n is not reachable at ${N8N_API}" >&2
  echo "Start the stack with: docker compose up -d" >&2
  exit 1
fi

echo "Fetching workflows from ${N8N_API}..."

WORKFLOWS=$(curl -sf -H "X-N8N-API-KEY: ${API_KEY}" \
  "${N8N_API}/api/v1/workflows?limit=500")

if [ -z "$WORKFLOWS" ] || [ "$WORKFLOWS" = "null" ]; then
  echo "Error: Failed to fetch workflow list" >&2
  exit 1
fi

COUNT=$(echo "$WORKFLOWS" | jq '.data | length')
echo "Found ${COUNT} workflows"

mkdir -p "$WORKFLOWS_DIR"

echo "$WORKFLOWS" | jq -r '.data[].id' | while read -r WF_ID; do
  WF_DATA=$(curl -sf -H "X-N8N-API-KEY: ${API_KEY}" \
    "${N8N_API}/api/v1/workflows/${WF_ID}")

  if [ -n "$WF_DATA" ] && [ "$WF_DATA" != "null" ]; then
    WF_NAME=$(echo "$WF_DATA" | jq -r '.name // "unknown"' | tr ' /' '_')
    echo "$WF_DATA" | jq '.' > "${WORKFLOWS_DIR}/${WF_ID}.json"
    echo "  Exported: ${WF_NAME} (${WF_ID})"
  else
    echo "  WARNING: Failed to export workflow ${WF_ID}"
  fi
done

echo "Workflows exported to $WORKFLOWS_DIR"
ls -1 "$WORKFLOWS_DIR"/*.json 2>/dev/null || true
