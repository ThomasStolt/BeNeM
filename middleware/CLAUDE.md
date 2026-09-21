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
| `main.py` | FastAPI app entry point. Defines `/register`, `/webhook`, `/health`, `/api/v1/incidents`, `/api/v1/tactical-overview`, `/api/v1/threshold-counts`, `/api/v1/maintenance-map` (in_maintenance + scheduled + host_down name lists), `/internal/cache/reload` endpoints and the lifespan startup handler. |
| `incident_cache.py` | Background incident cache: pre-fetches incidents + alarm details from BHNM, stores enriched results in memory, one asyncio.Task per enabled server with configurable pacing. |
| `tactical_cache.py` | Background tactical overview cache: pre-fetches category/site/app grouping data from BHNM, stores raw JSON in memory. Same lifecycle as `incident_cache.py`. |
| `threshold_cache.py` | Background threshold counts cache: pre-fetches `list-thresholds-csv` from BHNM, parses server-side, stores `{deviceName: count}` dict in memory. Reduces per-client payload from ~50 MB CSV to ~200 KB JSON at scale. |
| `config.py` | Loads all configuration from environment variables (via `python-dotenv`). No secrets in code. |
| `database.py` | SQLite helpers: `init_db`, `save_token`, `get_tokens_for_secrets` (and the single-secret wrapper `get_tokens_for_secret`), `get_all_tokens`, `delete_token`. |
| `apns.py` | APNs delivery: JWT generation, HTTP/2 POST via `httpx`, stale token detection. |
| `webpush.py` | Web Push delivery: VAPID-signed push via `pywebpush`, stale subscription detection. |
| `Dockerfile` | Builds the FastAPI app image. Uses `uvicorn` as the server. |
| `docker-compose.yml` | Runs `bhnm-apns` + `benem-admin` + `benem-pwa` + `caddy:2.9-alpine` together. Named volumes for SQLite and Caddy data. |
| `benem-admin/` | Sibling FastAPI service (separate container) providing the web admin portal: manages `servers.json`, per-server cache toggles, connection tests, and triggers `/internal/cache/reload` on this service. Has its own `main.py`, templates, and tests. |
| `Caddyfile` | Reverse proxy config: Caddy listens on 443, proxies to the FastAPI container, handles TLS automatically. |
| `requirements.txt` | Python dependencies: `fastapi`, `uvicorn`, `httpx[http2]`, `PyJWT`, `cryptography`, `python-dotenv`. |
| `upgrade.sh` | Upgrade script: pulls latest code, rebuilds all containers, restarts services, health-checks bhnm-apns and benem-admin. |
| `check-env.sh` | Validates `.env` for completeness and correctness. The only supported setup path is `.env.example` → edit → `check-env.sh`. |
| `.env.example` | Template for `.env`. Committed to the repo — never commit `.env` itself. |
| `VERSION` | Plain text file containing the current version; the source of truth reported by `/health` (avoid duplicating the number in prose so it can't drift). |
| `bhnm-apns.service` | Systemd unit file (legacy, not used in Docker deployments). |

---

## The deploy pulls from origin — so "verify before pushing" is impossible

`upgrade.sh` runs `git fetch origin` and `git pull --ff-only`, and **exits early when the local
checkout already matches the remote**. The VPS deploys what is on origin, not what is on a
laptop. Any change that needs a deploy therefore cannot be verified before it is pushed.

**The order is: push → deploy → verify → revert on failure.** Not push-last. A revert is a
commit and a redeploy, and the tagged previous images cover the containers, so a failed
verification is recovered forwards rather than prevented backwards.

Written down because the opposite instruction — "push after the verification passes, not
before" — was issued in review on 2026-09-15 and is not achievable with this pipeline. It is a
reasonable-sounding rule that this repository's deploy mechanism cannot honour, so it will be
re-issued unless it is refused here.

**On failure, revert immediately and without asking.** Leaving failed code on `main` while
waiting for a reply is the worse of the two risks: `main` is what the next deploy pulls.

## A return value of zero that nobody checks is how a no-op stays invisible

`note_state_override_any_server()` returns the number of servers patched, and `main.py` logs
`if n:`. When an incident is acknowledged before its first cache cycle there is nothing to patch,
so `n` is 0 — **no patch, no log, no error**. Measured 2026-09-15: in the whole persisted log
`Cache patched` appears three times and every one is `-> CLOSED`; never once `-> ACKNOWLEDGED`.

The general rule, which is cheap and applies to every helper here that counts what it did: **if a
function returns "how many things I affected", the zero case is a finding and must be logged.**
Silence on zero makes a broken path and an idle one look identical, which is the operational form
of the doctrine in the root `CLAUDE.md`.

## Upgrade runbook

**Dump the container log before every deploy.** `docker compose up -d` recreates the
container and `docker logs` starts empty; this erased the webhook evidence being
measured on 2026-09-03 and again on 2026-09-14.

```bash
mkdir -p /root/logdumps
docker logs -t benem-middleware > /root/logdumps/benem-middleware-$(date -u +%Y%m%dT%H%M%SZ)-pre-<version>.log 2>&1
```

Since 2.13.1 the app also mirrors stdout to `/logs/middleware.log` on the `./logs`
bind mount (rotated 5 MB x 5), which survives recreation — but take the dump anyway
until that has proven itself across a few deploys.

### The persisted log lives at `/logs/middleware.log` — and only there

**Inside the container: `/logs/middleware.log`.** On the host:
`/root/BeNeM/middleware/logs/middleware.log`. The path comes from `HOST_LOG_PATH`
(`main.py:357`), which defaults to `/logs/middleware.log` and is normally unset.

**`/app/logs/middleware.log` is NOT the log. Never read it.** On 2026-09-16 that path held a
1 MB file with the right name, the right opening line, and real content — an exact byte-prefix of
the live log, left behind by a `docker cp` at 19:19:29Z. **It answers greps about anything later
with silence, and silence is the same answer the real log gives when the event did not happen.**
It produced a correct-looking negative result for a webhook search. Full write-up: evidence §8.17.

Two rules follow:

- **Never copy a log *into* the container.** Read it in place (`docker exec … grep`) or copy it
  *out* to the session scratchpad. A copy inside the container looks exactly like the real thing
  and outlives the session that made it.
- **Never trust a silence: make the log prove it was writing during the window first.** Before an
  absence is allowed to mean anything, show timestamped lines from inside the window being asked
  about. This is "search for the object, never trust the count" applied to time, and it is the only
  reason the orphan above was caught rather than believed.
- **An empty result must first be shown capable of returning a non-empty one.** The generalisation
  of the rule above, to every probe and not just log greps. Twice on 2026-09-19 an absence was
  reported as a finding when the absence was in the query: a webhook watch whose filter matched a
  startup banner instead of a delivery, and an incident probe that read `d["incidents"]` when the
  payload's key is `active_incidents` — it returned "no incidents to acknowledge" while the log
  beside it said `Cache updated: 6 active`. Run the probe against a case you know is non-empty, or
  say "did not find" rather than "is not there".
- **And the same rule for assertions: one must first be shown to have been checked.** On the same
  day, "the ack user reads as the device name" was stated in review, accepted without a check, and
  a constant was ruled on it. The producer's own record — `benem-admin`'s `/app/log/admin.jsonl` —
  said those strings were usernames someone typed, and a released build broke attribution before
  anybody read it. An unverified assertion in a review is the same defect as an unverified green
  affordance in a UI: a claim presented as a measurement.

Then: `./upgrade.sh`, confirm `/health` reports the expected version, and keep the
previous image tagged for rollback (`docker tag bhnm-apns-bhnm-apns:latest bhnm-apns-bhnm-apns:<sha>`).

### If a deploy step edits `servers.json`: never write it with an atomic rename

`docker-compose.yml` bind-mounts `servers.json` as a **file**, not a directory:

```
- ./servers.json:/data/servers.json:ro      # bhnm-apns
- ./servers.json:/app/servers.json          # benem-admin
```

**A file bind mount binds the inode, not the path.** `os.replace()` — write a temp file, rename
it over the target — is the *correct* safe-write idiom everywhere else, and exactly wrong here:
it creates a new inode, and the containers go on reading the old one. The host shows the new
content, the container shows the old, and **nothing errors**.

Measured 2026-09-15 while seeding `webhook_secrets` for S1 1a: host inode 26419 with the seeded
lists, container inode 17049 with none, and the middleware correctly logging
`[Webhook] FALLBACK — no server lists secret_fp=…` for the value that had just been seeded.

- **Do:** write in place — `open(path, "r+")`, write, `truncate()`.
- **If a rename already happened:** the mount is stale until the containers that mount the file
  are recreated — `docker compose up -d --force-recreate bhnm-apns benem-admin`.

**Why this never bit before:** every previous `servers.json` edit went through the admin portal,
and `benem-admin/servers.py:save_servers()` writes in place. The trap only appears the first time
a deploy step edits the file directly, which is what made it a deploy-day surprise rather than a
known hazard.

---

## Deployment facts

- **Runtime:** Python / FastAPI
- **Deployed at:** `https://bhnm-apns.hurrikap.org` (Linode Nanode, Caddy terminates TLS)
- **APNs:** `.p8` Auth Key, base64-encoded in `APNS_PRIVATE_KEY_B64` env var
- **Web Push:** VAPID key pair, configured via `VAPID_PRIVATE_KEY`, `VAPID_PUBLIC_KEY`, `VAPID_CONTACT_EMAIL` env vars

---

## Key Design Decisions

### Per-Device `active_secret` Routing, and the per-server accepted list (2.15.0)
When BeNeM registers a device via `POST /register`, it sends `X-Webhook-Token: <secret>` — this value is stored as `active_secret` in the `device_tokens` SQLite row. When a webhook arrives at `POST /webhook?secret=<value>`, only devices reachable from that secret receive the notification.

Since **2.15.0 (S1 change 1a)** the webhook additionally **resolves which server the secret belongs to**, via `webhook_secrets` in `servers.json` (`config.server_accepted_secrets()`), and fans out over that server's whole accepted list. It is a *list* because rotation needs an overlap window — old and new accepted together while devices migrate. `/register` and `/register-webpush` also record `server_id`.

**A secret no server lists falls back to the pre-1a single-secret lookup.** That fallback is not tidiness: an unresolved webhook must page the devices it pages today, because the alternative is paging nobody.

There is still **no global `WEBHOOK_SECRET` environment variable in this service**. (`benem-admin` has one, as the seed/fallback for the QR while a server has no list — that is the contradiction with INSTALL.md §7.5, ruled 2026-09-15: the install guide was the wrong document and is corrected.) Authentication is implicit: possessing an accepted secret proves authorisation.

**Never log a secret, and never log a prefix of one** — a prefix is a piece of the secret. `main.secret_fingerprint()` gives eight hex characters of SHA-256, which is enough to tell two secrets apart in a log and tells an attacker nothing.

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
- `webhook_secrets` (list of strings, default empty) — the webhook secrets this server accepts. Empty means the pre-1a fallback. **`benem-admin` must write this key back on every save**; it once rebuilt entries from a fixed key list, which would have erased every accepted list and silently stopped paging every device.
- `cache_enabled` (bool, **default true** since 2.11.0; single home `config.CACHE_ENABLED_DEFAULT`, mirrored in `benem-admin/servers.py`) — set `false` to opt a server out. Gates all four crawlers: incidents, tactical, thresholds, maintenance map.
- `cache_refresh_seconds` (int, default 120, min 60, max 900) — full cycle interval
- `retain_closed` (bool, **default false**; single home `config.CLSD_RETENTION_DEFAULT`, mirrored in `benem-admin/servers.py`) — M3/C15. When on, an incident that gets a `RECOVERY` or simply disappears from the list is kept as `state: "CLOSED"` with a `closed_at`, served for 24 hours and then dropped. **OFF until iOS 2.14.0 and PWA 0.19.0 are in the field**: build 53's list applies no status filter at all, so a retained closed row would appear in it with no pill to hide it. Not portal-editable, but it round-trips a portal save — omitting it from `save_servers` would silently turn retention back off.

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
| `POST /api/v1/incidents/refresh` | C7/M2 — ONE `getincidents` for the caller's server, single-flight, at most one per server per 30 s, no `getincidentdetail` call. Independent of the polling switch: BHNM sends no webhook for `ALARMS CLEARED`, so a list call is the only way that state arrives | iOS app, PWA |
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

## Running the tests

One command covers the whole middleware suite (all test modules live under `tests/`;
a root-level `test_endpoints.py` used to be skipped by `pytest tests` — moved 2026-09-03):

```bash
cd middleware && python -m pytest tests
```

Since 2.14.0 this collects **everything** — `test_database.py`, `test_proxy_auth.py` and
`test_webpush.py` were moved into `tests/`. They previously sat at `middleware/` root where the
documented command never reached them, which is how `test_webpush.py` stayed red unnoticed.

The admin portal is a separate app with its own suite:

```bash
cd middleware/benem-admin && python -m pytest
```

Both need a venv with `requirements.txt` (plus `benem-admin/requirements-dev.txt` for the
admin). Report counts from these two commands only — never from a subset.

**Gate on pytest's own exit code.** A commit chain that reads
`pytest ... | tail -1 && git commit` gates on `tail`, not on pytest — a red suite was
committed that way on 2026-09-03. In any script: run pytest with **no pipe** and
`&&` the commit to it, or `set -o pipefail` first. Human-readable form:

```bash
cd middleware && python -m pytest tests -q && echo GREEN   # && binds to pytest, not to a pipe
```

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
