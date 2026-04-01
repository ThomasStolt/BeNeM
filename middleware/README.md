# bhnm-apns

> Open source APNs push notification middleware for [BeNeM](https://github.com/ThomasStolt/BeNeM) — bridges BMC Helix Network Management (BHNM) incident webhooks to Apple Push Notifications on iPhone.

![Python](https://img.shields.io/badge/python-3.11+-blue) ![License](https://img.shields.io/badge/license-MIT-green) ![Docker](https://img.shields.io/badge/docker-compose-blue)

---

## What it is

bhnm-apns is a lightweight FastAPI middleware that receives incident webhooks from a self-hosted BHNM server and forwards them as push notifications to the BeNeM iOS app via APNs (Apple Push Notification service). It handles per-server routing, APNs JWT authentication, and automatic cleanup of stale device tokens. Deploy it once on any VPS or cloud instance — Caddy handles TLS automatically.

```
BHNM Server  ──webhook──►  bhnm-apns  ──APNs──►  iPhone (BeNeM)
```

---

## Features

- Push notifications for BHNM incidents delivered to iPhone in real time
- Per-server routing: each BHNM server uses its own unique webhook secret, so only matching registered devices receive notifications
- **BeNeM Admin portal** — dark-mode web UI for generating BeNeM registration QR codes / deep-links, testing server connectivity, viewing registered devices, and managing settings. Protected by TOTP authentication with brute-force rate limiting.
- BHNM API proxy — forwards BeNeM app requests to BHNM servers on private networks via `X-BHNM-Target` header
- Automatic TLS via Caddy (Let's Encrypt — no manual certificate management)
- SQLite persistence via Docker named volume — device tokens survive container restarts
- HTTP/2 APNs delivery with automatic cleanup of expired or invalid device tokens
- Incident deep-link support: notifications tap directly to the incident in BeNeM
- Single `docker compose up -d` deployment on any Linux VPS

---

## Prerequisites

- A Linux VPS or cloud instance with a public IP and a domain name pointing to it
- Docker and Docker Compose installed
- An Apple Developer account with an APNs Auth Key (`.p8`) for the BeNeM bundle ID

---

## Quick Start

1. **Clone the repository**
   ```bash
   git clone https://github.com/ThomasStolt/bhnm-apns.git
   cd bhnm-apns
   ```

2. **Copy the example configuration**
   ```bash
   cp .env.example .env
   ```
   Alternatively, run the interactive setup wizard:
   ```bash
   ./setup.sh
   ```

3. **Fill in `.env`** (see [Configuration](#configuration) below)

4. **Point your domain at this server**
   Create an DNS A record: `your-domain.example.com → <server IP>`

5. **Start the service**
   ```bash
   docker compose up -d
   ```
   Caddy will obtain a TLS certificate automatically on first start.

6. **Generate a webhook secret per BHNM server**
   ```bash
   openssl rand -hex 32
   ```

7. **Configure BHNM** — add a webhook with URL:
   ```
   https://your-domain.example.com/webhook?secret=<your-secret>
   ```

8. **Configure BeNeM** — in Settings → BHNM Server, enter:
   - Middleware URL: `https://your-domain.example.com`
   - Webhook Secret: `<same secret>`

---

## Configuration

All configuration is via environment variables in `.env`. Never commit `.env` — it is gitignored.

| Variable | Required | Description | Example |
|---|---|---|---|
| `APNS_KEY_ID` | Yes | APNs Auth Key ID (10 chars, from Apple Developer) | `ABC1234567` |
| `APNS_TEAM_ID` | Yes | Apple Developer Team ID (10 chars) | `XYZ9876543` |
| `APNS_BUNDLE_ID` | Yes | App bundle identifier | `com.tstolt.benem` |
| `APNS_PRIVATE_KEY_B64` | Yes | Contents of `.p8` file, base64-encoded. Generate: `base64 -w 0 AuthKey_XXXX.p8` | `LS0tLS1CRUd...` |
| `DOMAIN` | Yes | Public domain for this service — used by Caddy for automatic TLS | `bhnm-apns.example.com` |
| `MIDDLEWARE_PORT` | No | Internal port the FastAPI app listens on. Default: `8889` | `8889` |

---

## Per-Server Routing

bhnm-apns supports multiple BHNM servers simultaneously. Each server has its own unique webhook secret. When a device registers via `/register`, the `X-Webhook-Token` header value is stored as `active_secret` for that device. When a webhook arrives with `?secret=<value>`, only devices whose `active_secret` matches receive the notification.

This means:
- Users with BeNeM configured against Server A receive only Server A alerts
- Users with BeNeM configured against Server B receive only Server B alerts
- There is no global shared secret — each secret is generated independently per server

**Generate a secret for each BHNM server:**
```bash
openssl rand -hex 32
```

---

## BHNM Webhook Configuration

In BHNM, create a new webhook notification contact with:

**URL:**
```
https://your-domain.example.com/webhook?secret=YOUR_SECRET
```

**Method:** POST
**Content-Type:** `application/json`

**Payload template:**
```json
{
  "notification_type": "$NOTIFICATIONTYPE",
  "hostname": "$HOSTNAME",
  "host_state": "$HOSTSTATE",
  "site": "$HOSTALIAS",
  "service_desc": "$SERVICEDESC",
  "output": "$SERVICEOUTPUT",
  "incident_id": "$SERVICEPROBLEMID"
}
```

For host-only alerts, replace `$SERVICEOUTPUT` with `$HOSTOUTPUT` and `$SERVICEPROBLEMID` with `$HOSTPROBLEMID`.

---

## API Reference

### `POST /register`

Registers an APNs device token. Called automatically by BeNeM on app launch.

**Headers:**
- `X-Webhook-Token: <secret>` (required) — the webhook secret configured in BeNeM Settings

**Body (JSON):**
```json
{
  "token": "<APNs device token>",
  "device_name": "Thomas's iPhone",
  "environment": "production"
}
```

The `environment` field tells the middleware which APNs endpoint to use for this token. BeNeM sends `"sandbox"` for Debug/Xcode builds and `"production"` for Release/TestFlight/App Store builds. Defaults to `"production"` if omitted.

**Response:**
```json
{ "status": "ok" }
```

---

### `POST /webhook?secret=<value>`

Receives an incident webhook from BHNM and forwards it as a push notification to all devices registered with the matching secret.

**Query parameter:**
- `secret` (required) — must match the `active_secret` of the target devices

**Body (JSON):** BHNM notification payload (see [BHNM Webhook Configuration](#bhnm-webhook-configuration))

**Response:**
```json
{ "status": "ok", "notified": 2 }
```

---

### `GET /health`

Returns service status. No authentication required.

**Response:**
```json
{
  "status": "running",
  "version": "2.2.0",
  "registered_devices": 3,
  "apns_environment": "per-device"
}
```

---

## Development (without Docker)

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

## Updating

```bash
git pull
docker compose build
docker compose up -d
```

---

## Admin Portal

The `benem-admin` service provides a dark-mode web UI accessible at `https://your-domain.example.com/admin/`. It is protected by TOTP authentication (Google Authenticator, 1Password, Authy).

**Pages:**
- **Generate Link** — select a server, enter a username and customise the app icon and accent colour, then generate a `benem://` deep-link and QR code for BeNeM registration
- **Connection Test** — verify DNS, HTTPS reachability, and API authentication for each configured BHNM server
- **Push Config** — view middleware endpoints and all registered devices
- **Log** — audit trail of every generated registration link
- **Settings** — TOTP QR code setup, app version, container restart

**Required environment variables for benem-admin:**

| Variable | Description |
|---|---|
| `MIDDLEWARE_URL` | Public URL of this bhnm-apns instance |
| `WEBHOOK_SECRET` | Default webhook secret embedded in generated links |
| `TOTP_SECRET` | Base32 TOTP secret (generate: `python -c "import pyotp; print(pyotp.random_base32())"`) |
| `SESSION_SECRET` | Random string for signing session cookies (generate: `openssl rand -hex 32`) |
| `BENEM_SECRET_KEY` | 32-byte hex key for encrypting benem:// payloads (generate: `openssl rand -hex 32`) |

`servers.json` (in the benem-admin working directory) defines available BHNM servers. This file contains API keys and must never be committed to version control — it is listed in `.gitignore`.

---

## Contributing

Bug reports and feature requests: [BeNeM Issues](https://github.com/ThomasStolt/BeNeM/issues)

---

## License

[MIT](LICENSE) — Copyright (c) 2025 Thomas Stolt
