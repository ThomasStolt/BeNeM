# Changelog

All notable changes to bhnm-apns are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [2.0.0] - 2026-03-26

### Changed
- **Per-device active-secret routing**: each BHNM server now uses its own unique webhook secret. `/webhook` forwards only to devices whose `active_secret` matches the incoming `?secret=` value.
- `/register` now stores the `active_secret` from the `X-Webhook-Token` header on a per-device basis. An empty header returns HTTP 400.
- `/webhook` now requires `?secret=` query parameter. An empty value returns HTTP 400.
- Removed global `WEBHOOK_SECRET` environment variable — authentication is now implicit and per-server (knowing the secret is the proof of authorisation).
- Database migration: `active_secret TEXT NOT NULL DEFAULT ''` column added to `device_tokens`. Existing installs are migrated automatically on first startup (safe `ALTER TABLE` with `OperationalError` ignored).
- `/health` response now includes `version` field.
- Startup log now prints middleware version and confirms per-device routing is enabled.

### Removed
- `WEBHOOK_SECRET` from `config.py` and `.env.example`
- `require_auth` function and `APIKeyHeader` dependency from `main.py`

---

## [1.0.0] - 2026-03-25

### Added
- Initial release: FastAPI middleware bridging BHNM webhooks to Apple Push Notifications (APNs).
- APNs HTTP/2 delivery via `httpx` with automatic token cleanup on 410 Gone / 400 BadDeviceToken.
- Incident deep-link support: `incident_id` embedded in APNs payload for direct navigation in BeNeM.
- Docker + Caddy deployment: automatic TLS via Let's Encrypt, single `docker compose up -d` setup.
- SQLite persistence via Docker volume (`/data/bhnm_apns.db`).
- Single shared-secret authentication via `X-Webhook-Token` header or `?secret=` query parameter.
- `setup.sh` interactive setup wizard generating `.env` from prompts.
