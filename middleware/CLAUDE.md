# BeNeM Middleware (bhnm-apns) — Claude Code Context

Python / FastAPI middleware that bridges BMC Helix Network Management
(BHNM) incident webhooks to Apple Push Notifications (APNs) and Web Push
(PWA/Android). Also provides an incident caching layer that pre-fetches
and enriches incident data for fast client loading.

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
| `main.py` | FastAPI app entry point. Defines `/register`, `/webhook`, `/health`, `/api/v1/incidents`, `/api/v1/tactical-overview`, `/internal/cache/reload` endpoints and the lifespan startup handler. |
| `incident_cache.py` | Background incident cache: pre-fetches incidents + alarm details from BHNM, stores enriched results in memory, one asyncio.Task per enabled server with configurable pacing. |
| `tactical_cache.py` | Background tactical overview cache: pre-fetches category/site/app grouping data from BHNM, stores raw JSON in memory. Same lifecycle as `incident_cache.py`. |
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
| `VERSION` | Plain text file containing the current version (`2.4.0`). |
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

### Incident Cache
`incident_cache.py` pre-fetches incidents and their alarm details from each BHNM server with caching enabled. One `asyncio.Task` per server runs a continuous loop:

1. Calls `getincidents` (1 API call) to get the incident list
2. Calls `getincidentdetail` per incident (N API calls), paced evenly over the configured refresh interval to avoid overloading BHNM
3. Enriches each incident with `alarm_counts` (red/orange/yellow/green/blue) and `alert_type`
4. Stores the enriched result in an in-memory dict keyed by `server_id`

Clients call `GET /api/v1/incidents` and receive the full incident list with alarm counts in a single response. If the cache is cold (startup, new server), the endpoint falls through to the live BHNM proxy.

Configuration is per-server in `servers.json`:
- `cache_enabled` (bool, default false) — opt-in per server
- `cache_refresh_seconds` (int, default 120, min 60, max 900) — full cycle interval

The admin portal provides a toggle switch and refresh interval input per server. On add/edit/delete, the admin POSTs to `/internal/cache/reload` to start/stop/restart the cache loop.

Server resolution for the cache uses `X-Proxy-Token` (matched against `api_key` in servers.json) or `X-BHNM-Target` header (matched against server `url`).

### Tactical Overview Cache
`tactical_cache.py` pre-fetches tactical overview data (category, site, app grouping types) from each BHNM server with caching enabled. One `asyncio.Task` per server runs a continuous loop:

1. Calls `POST /fw/index.php?r=restful/tactical-overview/data` for each grouping type (3 API calls)
2. Stores the raw JSON response in an in-memory dict keyed by `(server_id, grouping_type)`

Clients call `GET /api/v1/tactical-overview?grouping_type=category` and receive the data instantly. If the cache is cold, the endpoint falls through to a live BHNM request (building the proper form-encoded POST from the proxy token).

Configuration shares `cache_enabled` and `cache_refresh_seconds` with the incident cache. Admin portal reload (`/internal/cache/reload`) restarts both caches.

---

## Endpoints

| Endpoint | Purpose | Consumer |
|---|---|---|
| `GET/POST /api/v1/incidents` | Cached enriched incidents with alarm counts; falls through to live BHNM proxy if cache is cold | iOS app, PWA |
| `GET /api/v1/tactical-overview` | Cached tactical overview data by grouping type (`category`, `site`, `app`); falls through to live BHNM if cache is cold | iOS app, PWA |
| `POST /internal/cache/reload` | Trigger cache restart for a server (called by admin portal on server add/edit/delete) | Admin portal |
| `POST /register` | Register an APNs device token (with `active_secret` from `X-Webhook-Token` header) | iOS app |
| `DELETE /register` | Unregister an APNs device token | iOS app |
| `POST /register-webpush` | Register a Web Push subscription (with webhook secret from `X-Webhook-Token` header) | PWA |
| `GET /vapid-key` | Return the VAPID public key for Web Push subscription | PWA |
| `POST /webhook` | Receive a BHNM incident event and fan out push notifications | BHNM |
| `GET /health` | Health check — returns version, device count, and cache status per server | Ops |
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
