#!/bin/sh
# Auto-create an n8n API key on first boot (if not already seeded)
# Uses Node.js because BusyBox wget lacks cookie support

API_KEY_FILE="/home/node/.n8n/.api-key"

# Skip if API key already exists on disk
if [ -f "$API_KEY_FILE" ] && [ -s "$API_KEY_FILE" ]; then
  echo "[$(date)] API key already exists at ${API_KEY_FILE}, skipping"
  exit 0
fi

echo "[$(date)] Logging in as ${N8N_INSTANCE_OWNER_EMAIL}..."

# Retry login up to 5 times with 3s delay (n8n may still be initializing after healthcheck)
TRIES=0
MAX_TRIES=5
RESULT=""
until [ "$TRIES" -ge "$MAX_TRIES" ]; do
  TRIES=$((TRIES + 1))
  RESULT=$(node -e "
const http = require('http');

function request(method, apiPath, body, cookies) {
  return new Promise((resolve, reject) => {
    const opts = {
      hostname: 'localhost',
      port: parseInt(process.env.N8N_PORT || '5678'),
      path: apiPath,
      method,
      headers: { 'Content-Type': 'application/json' }
    };
    if (cookies) opts.headers['Cookie'] = cookies;
    const req = http.request(opts, res => {
      let data = '';
      res.on('data', d => data += d);
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: data }));
    });
    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

(async () => {
  const loginRes = await request('POST', '/rest/login', {
    emailOrLdapLoginId: process.env.N8N_INSTANCE_OWNER_EMAIL,
    password: process.env.N8N_INSTANCE_OWNER_PASSWORD
  });

  const setCookies = loginRes.headers['set-cookie'] || [];
  const cookies = setCookies.map(c => c.split(';')[0]).join('; ');

  if (!loginRes.body.includes('\"data\"')) {
    console.error('Login failed: ' + loginRes.status);
    process.exit(1);
  }
  console.error('Login successful');

  const scopesRes = await request('GET', '/rest/api-keys/scopes', null, cookies);
  const allScopes = JSON.parse(scopesRes.body).data;

  const label = 'backup-automation-' + Date.now();
  const expiresAt = Date.now() + 365 * 24 * 60 * 60 * 1000;

  const keyRes = await request('POST', '/rest/api-keys', {
    label,
    expiresAt,
    scopes: allScopes
  }, cookies);

  const parsed = JSON.parse(keyRes.body);
  if (parsed && parsed.data && parsed.data.rawApiKey) {
    console.log(parsed.data.rawApiKey);
  } else {
    console.error('API key creation failed: ' + keyRes.body);
    process.exit(1);
  }
})();
" 2>&1)

  if echo "$RESULT" | grep -q "^eyJ"; then
    break
  fi
  echo "[$(date)] Login attempt ${TRIES}/${MAX_TRIES} failed, retrying in 3s..."
  sleep 3
done

RAW_API_KEY=$(echo "$RESULT" | grep "^eyJ" | head -1)
LOGIN_MSG=$(echo "$RESULT" | grep -v "^eyJ")

echo "[$(date)] ${LOGIN_MSG}"

if [ -z "$RAW_API_KEY" ]; then
  echo "[$(date)] ERROR: API key creation failed after ${MAX_TRIES} attempts"
  exit 1
fi

echo "$RAW_API_KEY" > "$API_KEY_FILE"
chmod 600 "$API_KEY_FILE"
echo "[$(date)] API key saved to ${API_KEY_FILE}"
