# BeNeM Middleware (bhnm-apns) — Claude Code Context

Python / FastAPI middleware that bridges BMC Helix Network Management
(BHNM) incident webhooks to Apple Push Notifications (APNs) — and, in the
future, to Web Push for the PWA.

> Part of the BeNeM monorepo. See `../CLAUDE.md` for the cross-cutting
> architecture, `../ios/CLAUDE.md` for the iOS consumer, and
> `../shared/push-payload-spec.md` for the payload contract shared with
> consumers. History merged from `github.com/ThomasStolt/bhnm-apns`
> (April 2026 monorepo restructure) with full per-file history preserved.

Runs as a Docker container (with Caddy for TLS) on any VPS, receives JSON
webhook POSTs from a BHNM server, and forwards them as push notifications
to registered iOS devices (APNs) and Android/web users (Web Push).

---

## Project Structure

| File | Description |
|---|---|
| `main.py` | FastAPI app entry point. Defines `/register`, `/webhook`, `/health` endpoints and the lifespan startup handler. |
| `config.py` | Loads all configuration from environment variables (via `python-dotenv`). No secrets in code. |
| `database.py` | SQLite helpers: `init_db`, `save_token`, `get_tokens_for_secret`, `get_all_tokens`, `delete_token`. |
| `apns.py` | APNs delivery: JWT generation, HTTP/2 POST via `httpx`, stale token detection. |
| `webpush.py` | Web Push delivery: VAPID-signed push via `pywebpush`, stale subscription detection. |
| `Dockerfile` | Builds the FastAPI app image. Uses `uvicorn` as the server. |
| `docker-compose.yml` | Runs `bhnm-apns` + `benem-admin` + `benem-pwa` + `caddy:2.9-alpine` together. Named volumes for SQLite and Caddy data. |
| `Caddyfile` | Reverse proxy config: Caddy listens on 443, proxies to the FastAPI container, handles TLS automatically. |
| `requirements.txt` | Python dependencies: `fastapi`, `uvicorn`, `httpx[http2]`, `PyJWT`, `cryptography`, `python-dotenv`. |
| `upgrade.sh` | Upgrade script: pulls latest code, rebuilds all containers, restarts services, health-checks bhnm-apns and benem-admin. |
| `setup.sh` | Interactive shell wizard that generates `.env` from user prompts. |
| `.env.example` | Template for `.env`. Committed to the repo — never commit `.env` itself. |
| `VERSION` | Plain text file containing the current version (`2.3.0`). |
| `bhnm-apns.service` | Systemd unit file (legacy, not used in Docker deployments). |

---

## Deployment facts

- **Runtime:** Python / FastAPI
- **Deployed at:** `https://bhnm-apns.hurrikap.org` (Linode Nanode, Caddy terminates TLS)
- **APNs:** `.p8` Auth Key, base64-encoded in `APNS_PRIVATE_KEY_B64` env var
- **Web Push:** VAPID key pair, configured via `VAPID_PRIVATE_KEY`, `VAPID_PUBLIC_KEY`, `VAPID_CONTACT_EMAIL` env vars

---

## Key Design Decisions

### Per-Device `active_secret` Routing
Each BHNM server has its own unique webhook secret. When BeNeM registers a device via `POST /register`, it sends `X-Webhook-Token: <secret>` — this value is stored as `active_secret` in the `device_tokens` SQLite row. When a webhook arrives at `POST /webhook?secret=<value>`, only devices with a matching `active_secret` receive the notification. This enables a single middleware instance to serve multiple BHNM servers without cross-contamination of alerts.

There is **no global `WEBHOOK_SECRET` environment variable**. Authentication is implicit: possessing the correct secret proves authorisation.

### Dual APNs environment
The middleware routes per-device-token to sandbox or production APNs endpoints — the same registered device can be served from either pool. See `apns.py`.

### SQLite via Docker Volume
`database.py` uses SQLite at `/data/bhnm_apns.db`. `/data` is a Docker named volume (`db-data`), so tokens persist across container rebuilds. For non-Docker installs, `DB_PATH` env var overrides the path. Schema migrations (e.g. adding `active_secret`) are applied with a safe `ALTER TABLE ... ADD COLUMN` wrapped in a try/except that silently ignores `OperationalError` (column already exists).

### Caddy for TLS
Caddy handles Let's Encrypt certificate issuance and renewal automatically. The `DOMAIN` env var is injected into the Caddyfile via Docker Compose. No manual certificate management is needed.

### Env-Only Configuration
All secrets and configuration live in `.env` (gitignored). `config.py` reads them via `os.environ` / `python-dotenv`. Never hardcode secrets or commit `.env`.

### APNs JWT Authentication
`apns.py` generates a signed JWT (ES256) using the `.p8` private key, which is stored base64-encoded in `APNS_PRIVATE_KEY_B64`. The JWT is cached and refreshed every 55 minutes (APNs requires refresh before 60 min). HTTP/2 is used via `httpx`.

---

## Endpoints

| Endpoint | Purpose | Consumer |
|---|---|---|
| `POST /register` | Register an APNs device token (with `active_secret` from `X-Webhook-Token` header) | iOS app |
| `DELETE /register` | Unregister an APNs device token | iOS app |
| `POST /register-webpush` | Register a Web Push subscription (with webhook secret from `X-Webhook-Token` header) | PWA |
| `GET /vapid-key` | Return the VAPID public key for Web Push subscription | PWA |
| `POST /webhook` | Receive a BHNM incident event and fan out push notifications | BHNM |
| `GET /health` | Health check — returns version and registered device count | Ops |
| `POST /api/proxy/incident/acknowledge` | Proxy incident acknowledge to BHNM (auth via `X-Proxy-Token`) | iOS app, PWA |
| `POST /api/proxy/incident/unacknowledge` | Proxy incident unacknowledge to BHNM (auth via `X-Proxy-Token`) | iOS app, PWA |
| `POST /api/proxy/ha-status` | Proxy HA status check to BHNM (auth via `X-Proxy-Token`) | iOS app, PWA |
| `{path:path}` | Catch-all BHNM API proxy (auth via `X-Proxy-Token`, target via `X-BHNM-Target` or `servers.json` lookup) | iOS app, PWA |

---

## Push payload contract

The APNs custom-data payload is:

```json
{ "aps": { "alert": {...}, "sound": "default" }, "incident_id": "<id>" }
```

All notification payload types (current and future) are defined in
`../shared/push-payload-spec.md`. When adding a new notification type,
update that spec first, then implement here.

---

## Running Locally (without Docker)

```bash
pip install -r requirements.txt

export APNS_KEY_ID=test
export APNS_TEAM_ID=test
export APNS_BUNDLE_ID=com.tstolt.benem
export APNS_PRIVATE_KEY_B64=$(echo "dummy" | base64)
export DB_PATH=/tmp/bhnm_test.db

uvicorn main:app --reload --port 8889
```

---

## Manual Testing

```bash
# Health check
curl http://localhost:8889/health

# Register a device token
curl -X POST http://localhost:8889/register \
  -H "Content-Type: application/json" \
  -H "X-Webhook-Token: mysecret123" \
  -d '{"token": "abc123def456", "device_name": "Test iPhone"}'

# Send a test webhook (replace secret with the one used during register)
curl -X POST "http://localhost:8889/webhook?secret=mysecret123" \
  -H "Content-Type: application/json" \
  -d '{
    "notification_type": "PROBLEM",
    "hostname": "core-switch-01",
    "host_state": "DOWN",
    "site": "HQ",
    "service_desc": "",
    "output": "Host is unreachable",
    "incident_id": "42"
  }'
```

---

## Deployment

```bash
# Initial deploy
git clone https://github.com/ThomasStolt/bhnm-apns.git
cd bhnm-apns
cp .env.example .env
# Edit .env with your values
docker compose up -d

# Update
git pull && docker compose build && docker compose up -d
```

Post-monorepo-restructure: the middleware now lives inside the BeNeM
monorepo. The standalone `ThomasStolt/bhnm-apns` repository will be
archived (see the monorepo spec). Deployment workflows may need updating
to pull from the monorepo subdirectory.

---

## What NOT to Do

- **Never** log full device tokens — always truncate: `token[-8:]`
- **Never** commit `.env` — it contains APNs private key material and webhook secrets
- **Never** hardcode any secret or credential in Python source files
- **Never** add a global `WEBHOOK_SECRET` back — routing is now per-device via `active_secret`
- **Never** modify `.env.example` to include real values

---

## BHNM API

Endpoint contracts are in `../shared/BHNM_API_REFERENCE.md`.
