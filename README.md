# n8n Self-Hosted (Docker + PostgreSQL)

Docker Compose stack running **n8n** with **PostgreSQL**, automatic backups, and optional **Cloudflare Tunnel** for HTTPS/remote access.

## Quick Start

1. **Clone and create your env file:**

   ```sh
   git clone <repo-url> && cd n8n-self-hosted
   cp .env.example .env
   ```

2. **Generate secrets** — run each command and paste the output into `.env`:

   ```sh
   # Encryption key (required — never change after first use)
   openssl rand -hex 32

   # DB password (set both POSTGRES_PASSWORD and DB_POSTGRESDB_PASSWORD)
   openssl rand -base64 24

   # Runner auth token (set N8N_RUNNERS_AUTH_TOKEN)
   openssl rand -hex 32
   ```

   Then generate a **bcrypt hash** for `N8N_INSTANCE_OWNER_PASSWORD_HASH`:

   ```sh
   docker run --rm httpd:alpine htpasswd -bnBC 10 "" 'YOUR_STRONG_PASSWORD' | tr -d ':\n' | sed 's/$2y/$2a/'
   ```

   Set the same plaintext password in `N8N_INSTANCE_OWNER_PASSWORD`.

3. **Start:**

   ```sh
   docker compose up -d
   ```

4. **Open n8n:** [http://localhost:5678](http://localhost:5678) or your tunnel URL

   Log in with `N8N_INSTANCE_OWNER_EMAIL` / `N8N_INSTANCE_OWNER_PASSWORD` from your `.env`.

## First Boot

On first start the entrypoint automatically:

- Waits for PostgreSQL to be healthy
- Provisions the instance owner from env vars
- Creates an API key and saves it to the `n8n_data` volume (used by the backup container)
- Imports any JSON workflows from `./workflows/` if the database is empty

## Useful Commands

| Task | Command |
|------|---------|
| Start (detached) | `docker compose up -d` |
| Stop | `docker compose down` |
| View n8n logs | `docker compose logs -f n8n` |
| View all logs | `docker compose logs -f` |
| Pull workflows from n8n to disk | `./scripts/pull-workflows.sh` |

Data lives in named volumes `postgres_data` and `n8n_data`. `docker compose down -v` removes them (destructive).

## Workflow Management

- **Primary store:** PostgreSQL via the `n8n_data` volume
- **Hourly snapshot:** The backup container exports all workflows to `./workflows/` via the n8n API
- **Auto-import:** On fresh deploys with an empty DB, workflows from `./workflows/` are imported

**Recover from data loss** (e.g. after `docker compose down -v`):

```sh
docker compose down
docker volume rm <compose-project>_postgres_data <compose-project>_n8n_data
docker compose up -d   # entrypoint imports from ./workflows/
```

**Permanently delete a workflow** between hourly exports:

1. Delete it in the n8n editor
2. Sync the deletion: `./scripts/pull-workflows.sh`

## Cloudflare Tunnel

Exposes n8n over HTTPS with a stable DNS name for webhooks and remote access.

### Prerequisites

- A [Cloudflare](https://cloudflare.com/) account with a domain added
- `cloudflared` installed on your local machine ([install docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/))

### 1. Authenticate with Cloudflare

```sh
cloudflared tunnel login
```

Opens a browser — select the domain you want to use. This saves a certificate to `~/.cloudflared/cert.pem`.

### 2. Create the tunnel

```sh
cloudflared tunnel create n8n
```

Output shows the tunnel UUID (e.g. `a1b2c3d4-...`). A credentials file is created at `~/.cloudflared/<UUID>.json`.

### 3. Copy the credentials to this project

```sh
cp ~/.cloudflared/<UUID>.json ./cloudflared/
```

### 4. Configure the tunnel

```sh
cp cloudflared/config.example.yml cloudflared/config.yml
```

Edit `cloudflared/config.yml`:

```yaml
tunnel: <UUID>
credentials-file: /etc/cloudflared/<UUID>.json

ingress:
  - hostname: n8n.example.com
    service: http://n8n:5678
  - service: http_status:404
```

Replace `<UUID>` and `n8n.example.com` with your values.

### 5. Route DNS

```sh
cloudflared tunnel route dns <UUID> n8n.example.com
```

This creates a CNAME record pointing `n8n.example.com` to `<UUID>.cfargotunnel.com`. Verify it in the Cloudflare DNS dashboard (proxy must be enabled / orange cloud).

### 6. Update `.env`

Set these to match your public URL:

```
N8N_HOST=n8n.example.com
N8N_PROTOCOL=https
N8N_PROXY_HOPS=1
WEBHOOK_URL=https://n8n.example.com/
N8N_EDITOR_BASE_URL=https://n8n.example.com/
```

### 7. Start

```sh
docker compose up -d
```

n8n is now accessible at `https://n8n.example.com`.

## Pinned Versions

| Service | Image | Version |
|---------|-------|---------|
| n8n | `n8nio/n8n` | `2.25.6` |
| n8n Runner | `n8nio/runners` | `2.25.6` |
| PostgreSQL | `postgres` | `16-alpine` |
| Cloudflare Tunnel | `cloudflare/cloudflared` | `2026.5.2` |

Update these in `docker-compose.yml` when upgrading.

## Architecture

- **postgres** — PostgreSQL 16, internal network only, data in `postgres_data` volume
- **n8n** — n8n workflow engine with custom entrypoint for auto-seeding and workflow import
- **n8n-runner** — External task runner for Code nodes and concurrent execution
- **backup** — Cron jobs: hourly workflow export, daily DB dump, daily n8n data tarball to `./backups/`
- **cloudflare-tunnel** — (optional) Cloudflare Tunnel for HTTPS ingress
