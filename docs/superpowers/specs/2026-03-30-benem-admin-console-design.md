# BeNeM Admin Console — Design Spec
**Date:** 2026-03-30
**Status:** Approved

---

## Overview

A lightweight, secure web-based admin console hosted on the existing Linode server alongside the `bhnm-apns` push middleware. Its primary purpose is to generate `benem://` deep-link URLs (and QR codes) for provisioning BeNeM iOS app connections, without requiring access to the local development machine or the Xcode project.

---

## Architecture

### Deployment

A new Docker container (`benem-admin`) is added to the existing Linode server. It runs alongside the existing `bhnm-apns` container and shares the same `.env` file (mounted read-only).

```
Internet
   │
   ▼
Caddy (TLS + Basic Auth)
   ├── /webhook  →  bhnm-apns container  (unchanged)
   └── /admin    →  benem-admin container (new)
```

**Stack:** Python 3, FastAPI, Uvicorn — single Docker container.
`generate_benem_link.py` is imported as a library (not shelled out).
Log is an append-only JSON Lines file on disk, mounted as a Docker volume.

### Impact on existing infrastructure

- The `bhnm-apns` container is untouched — no code, config, or endpoint changes.
- Existing `benem://` links on users' phones remain valid as long as `BENEM_SECRET_KEY` is not rotated.
- Caddy gets one new `reverse_proxy` block. All existing routing is preserved.

---

## Security Model

Three layers of defence, in order:

### 1. Caddy Basic Auth (outer gate)
- Configured in `Caddyfile` with a bcrypt-hashed password.
- Blocks all unauthenticated traffic before it reaches the app.
- Rate limiting via Caddy to prevent brute-force.

### 2. TOTP (app-level, second factor)
- After passing Basic Auth, a login page requires a 6-digit TOTP code.
- Compatible with Google Authenticator, 1Password, Authy, etc.
- A session cookie is issued on success: `HttpOnly`, `Secure`, `SameSite=Strict`, 24-hour expiry.
- TOTP secret is never displayed in the UI after initial setup (only during first-time QR code setup in Settings).
- Implemented with the `pyotp` Python library.

### 3. Secrets strictly in environment
- The following are **only** in `.env`, never in the UI, never logged, never returned in API responses:

| Variable | Purpose |
|---|---|
| `BENEM_SECRET_KEY` | AES-256-GCM key for encrypting `benem://` link payloads |
| `WEBHOOK_SECRET` | bhnm-apns middleware authentication secret |
| `TOTP_SECRET` | TOTP seed for admin authentication |
| `BASIC_AUTH_USER` | Caddy Basic Auth username |
| `BASIC_AUTH_HASH` | Caddy Basic Auth bcrypt password hash |

### Adding a second admin
Add `TOTP_SECRET_2` to `.env` and a second credential to the `Caddyfile`. No code changes required.

---

## Multi-Server Configuration

Multiple BHNM servers are supported via a `servers.json` file mounted as a Docker volume. This file is managed manually on the server and is never committed to the repository.

```json
[
  {
    "id": "prod",
    "name": "Production",
    "url": "https://bhnm.corp.com",
    "api_key": "abc123",
    "pin": ""
  },
  {
    "id": "demo",
    "name": "Demo (SaaS)",
    "url": "https://bhnm.demo.netreo.com",
    "api_key": "xyz789",
    "pin": "1234"
  }
]
```

- The Generate Link form shows a server selector dropdown. Selecting a server updates the read-only URL field and Test button.
- The Push Middleware URL is always derived from the server's own hostname (env var), not per-server.
- Adding a new server = edit `servers.json` on the Linode box and restart the container.

---

## UI Structure

### Navigation (sidebar)
Five pages accessible from a persistent left sidebar.

---

### Page 1: Generate Link (default)
- **Server selector** — dropdown populated from `servers.json`
- **BHNM URL** — read-only, updates per selected server; "Test" button checks reachability
- **Push Middleware URL** — read-only, always from env; "Test" button checks reachability
- **Username** — free text field
- **SF Symbol** — searchable graphical grid picker
- **Accent Colour** — colour swatches + hex input field
- **Generate Link button** → inline result below:
  - `benem://` URL in monospace box
  - "Copy to clipboard" button
  - QR code rendered inline
- All generated links are appended to the log automatically

---

### Page 2: Connection Test
- Server selector dropdown
- "Run Test" button → step-by-step results: DNS resolution, HTTPS reachability, API authentication

---

### Page 3: Push Config
- Read-only display of middleware URL and webhook endpoint URL
- List of registered devices: device token (truncated) + registration timestamp
- Data pulled from `bhnm-apns` internal state

---

### Page 4: Log
- Full paginated view of the JSON Lines log file
- Each entry shows: timestamp, username, server name, truncated link
- Filter by server

---

### Page 5: Settings
- TOTP setup / reset — shows QR code for authenticator app enrolment
- App version info
- Restart container button — requires mounting the Docker socket (`/var/run/docker.sock`) into the container; this is a security trade-off to evaluate during implementation (alternative: restart manually via SSH)

---

## Log Format

Each generated link produces one JSON Lines entry:

```json
{
  "ts": "2026-03-30T17:42:00Z",
  "user": "Thomas",
  "server_id": "prod",
  "server_name": "Production",
  "link_prefix": "benem://configure?p=eyJi…"
}
```

The full `benem://` URL is **not** stored in the log (it contains an encrypted API key). Only the first ~20 characters of the payload are logged for traceability.

---

## Docker Compose Addition

```yaml
benem-admin:
  build: ./benem-admin
  restart: unless-stopped
  env_file: .env
  volumes:
    - ./servers.json:/app/servers.json:ro
    - benem-admin-log:/app/log
  expose:
    - "8001"
```

Named volume declaration:
```yaml
volumes:
  benem-admin-log:
```

Caddy addition:
```
handle /admin* {
  basicauth {
    {$BASIC_AUTH_USER} {$BASIC_AUTH_HASH}
  }
  reverse_proxy benem-admin:8001
}
```

---

## Out of Scope

- Sending links via email or other channels (user generates and shares manually)
- User management UI (second admin added via `.env` / `Caddyfile` edits)
- Editing `servers.json` from within the UI (managed on-server manually)
- Mobile-optimised layout (desktop admin tool only)
