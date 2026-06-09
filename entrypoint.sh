#!/bin/sh

DB_HOST="${DB_POSTGRESDB_HOST:-postgres}"
DB_PORT="${DB_POSTGRESDB_PORT:-5432}"

echo "[$(date)] Waiting for PostgreSQL at ${DB_HOST}:${DB_PORT}..."
TRIES=0
MAX_TRIES=30
until nc -z "${DB_HOST}" "${DB_PORT}" 2>/dev/null; do
  TRIES=$((TRIES + 1))
  if [ "$TRIES" -ge "$MAX_TRIES" ]; then
    echo "[$(date)] ERROR: PostgreSQL not reachable after ${MAX_TRIES} attempts"
    exit 1
  fi
  echo "[$(date)] PostgreSQL not ready (attempt ${TRIES}/${MAX_TRIES}), retrying in 2s..."
  sleep 2
done
echo "[$(date)] PostgreSQL is reachable"

echo "[$(date)] Starting n8n temporarily for seeding..."
n8n start &
N8N_PID=$!

echo "[$(date)] Waiting for n8n to be ready..."
TRIES=0
until wget -qO- http://localhost:${N8N_PORT:-5678}/healthz 2>/dev/null; do
  TRIES=$((TRIES + 1))
  if [ "$TRIES" -ge 30 ]; then
    echo "[$(date)] ERROR: n8n not reachable after 30 attempts"
    kill $N8N_PID 2>/dev/null; wait $N8N_PID 2>/dev/null || true
    exit 1
  fi
  sleep 2
done
echo "[$(date)] n8n is ready"
sleep 10

# Seed API key on first boot
if [ -n "${N8N_INSTANCE_OWNER_EMAIL:-}" ] && [ -n "${N8N_INSTANCE_OWNER_PASSWORD:-}" ]; then
  /scripts/create-api-key.sh || echo "[$(date)] WARNING: API key auto-creation failed"
fi

# Import workflows via API while temp n8n is running
API_KEY_FILE="/home/node/.n8n/.api-key"
if [ -f "$API_KEY_FILE" ] && [ -s "$API_KEY_FILE" ]; then
  export N8N_API_KEY=$(cat "$API_KEY_FILE" | tr -d '\n')
  node -e "
const http = require('http');
const fs = require('fs');
const path = require('path');
const apiKey = process.env.N8N_API_KEY;
const workflowDir = '/workflows';

function request(method, apiPath, body) {
  return new Promise((resolve, reject) => {
    const bodyStr = body ? JSON.stringify(body) : null;
    const opts = {
      hostname: 'localhost',
      port: parseInt(process.env.N8N_PORT || '5678'),
      path: '/api/v1' + apiPath,
      method,
      headers: {
        'Content-Type': 'application/json',
        'X-N8N-API-KEY': apiKey,
        'Accept': 'application/json'
      }
    };
    if (bodyStr) opts.headers['Content-Length'] = Buffer.byteLength(bodyStr);
    const req = http.request(opts, res => {
      let data = '';
      res.on('data', d => data += d);
      res.on('end', () => resolve({ status: res.statusCode, body: data }));
    });
    req.on('error', reject);
    if (bodyStr) req.write(bodyStr);
    req.end();
  });
}

(async () => {
  // Check if workflows already exist
  const listRes = await request('GET', '/workflows');
  const listData = JSON.parse(listRes.body);
  const existing = listData.data ? listData.data.length : 0;
  if (existing > 0) {
    console.error(existing + ' workflows found in DB — skipping import');
    return;
  }

  // Import from /workflows directory
  const files = fs.readdirSync(workflowDir).filter(f => f.endsWith('.json'));
  if (files.length === 0) {
    console.error('No workflow files found in ' + workflowDir);
    return;
  }
  let imported = 0;
  for (const file of files) {
    try {
      const wf = JSON.parse(fs.readFileSync(path.join(workflowDir, file), 'utf8'));
      const res = await request('POST', '/workflows', {
        name: wf.name,
        nodes: wf.nodes || [],
        connections: wf.connections || {},
        settings: {}
      });
      if (res.status === 201 || res.status === 200) {
        const id = JSON.parse(res.body).data?.id || JSON.parse(res.body).id;
        console.error('Imported: ' + wf.name + ' (' + id + ')');
        imported++;
      } else {
        console.error('Failed: ' + wf.name + ' - ' + res.status + ' ' + res.body.substring(0, 200));
      }
    } catch(e) {
      console.error('Error importing ' + file + ': ' + e.message);
    }
  }
  console.log('Imported ' + imported + ' of ' + files.length + ' workflows');
})();
" 2>&1
else
  echo "[$(date)] WARNING: No API key available — skipping workflow import"
fi

echo "[$(date)] Waiting for n8n to finish background tasks..."
sleep 15

echo "[$(date)] Stopping temporary n8n instance..."
kill $N8N_PID 2>/dev/null; wait $N8N_PID 2>/dev/null || true

exec n8n start
