# Changelog

All notable changes to bhnm-apns are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [2.3.0] - 2026-04-02

### Added

- **Generate Link page redesign** (benem-admin v1.2.0) — two-column layout with a form panel on the left and an always-visible result panel on the right, connected by a fat arrow-shaped Generate button with glass shimmer animation. Icon and colour selectors replaced with custom dropdowns showing actual SVG icons and colour swatches. Username is now required before generation (disabled button with tooltip). Result URL is truncated with CSS ellipsis and a copy button; full URL shown on hover after 0.5 s delay. Accessibility improvements (`aria-disabled`), safe DOM construction (no `innerHTML`), and SVG 2.0 standard `href` attributes throughout.
- **Favicon** — BMC red hexagon logo served as SVG via `/static/` mount, displayed on all admin portal pages.

### Improved

- **`upgrade.sh` now health-checks both containers** — after rebuild and restart, the script verifies that both `bhnm-apns` (port 8889) and `benem-admin` (port 8001) return healthy status. If either fails, the relevant container logs are shown before exiting with an error.
- **Cleaner upgrade output** — Docker build progress lines and empty lines are filtered from the build output for a more readable upgrade experience.

---

## [2.2.0] - 2026-04-01

### Added

- **Per-device APNs environment routing** — each device token is now stored with its own `apns_environment` (`sandbox` or `production`). The middleware routes notifications to the correct APNs host per token, allowing Xcode debug builds (sandbox) and TestFlight/App Store builds (production) to coexist on a single middleware instance.
- `POST /register` accepts a new `environment` field (`"sandbox"` or `"production"`, defaults to `"production"`). Invalid values are silently normalised to `"production"`.
- Database migration: `apns_environment TEXT NOT NULL DEFAULT 'production'` column added to `device_tokens`. Existing tokens are treated as production (safe default).

### Changed

- `send_notification` and `send_to_all` now select the APNs host per token instead of using a global setting.
- `/health` response `apns_environment` field now returns `"per-device"` instead of the former global value.

### Removed

- **`APNS_USE_SANDBOX`** environment variable — no longer needed. Removed from `config.py`, `.env.example`, `setup.sh`, and documentation. The APNs environment is now determined per device at registration time.

---

## [2.1.2] - 2026-03-31

### Security

- **Webhook secret no longer written to logs** — partial secret suffix was previously included in `[Webhook]`, `[Register]`, and `[Unregister]` log lines; removed to prevent secrets appearing in server access logs or log aggregators.
- **Reachability check returns generic error messages** — the `/admin/reachability-check` endpoint previously reflected raw `httpx` exception strings back to the browser (leaking internal hostnames or network details); errors are now logged server-side and a generic `"Connection failed"` message is returned to the client.
- **XSS fix in Generate Link page** — BHNM and middleware URLs were previously injected into JavaScript `onclick` string literals; replaced with `data-url`/`data-result` HTML attributes read by JavaScript via `dataset`, eliminating the injection vector.
- **Login brute-force protection** — added `slowapi` rate limiting (5 attempts/minute per IP) to `POST /admin/login`; exceeding the limit renders the login page with a friendly error rather than a raw 429 response.
- **`servers.json` added to `.gitignore`** — this file stores server URLs, API keys, and PINs and must never be committed; it was previously untracked but not explicitly excluded.

### Changed

- **benem-admin dark mode UI** (benem-admin v1.1.0) — complete visual redesign of all 7 admin portal templates. Replaced Tailwind CDN with a custom CSS design system using CSS variables. New typography stack: Syne (headings), IBM Plex Sans (body), JetBrains Mono (code/tokens). Dark colour palette (`#0c0c14` base, `#131320` cards), electric blue accent (`#4f8ef7`) with glow, pulsing green operational status dot in sidebar, active nav item shown via left-border glow instead of background fill, glowing success/fail icons on connection test results.
- **HTMX server-URL fragment updated** — the dynamically injected HTML returned by `GET /admin/server-url` now uses the new dark CSS classes and the `data-url` attribute pattern consistent with the XSS fix above.
- `slowapi` added to `benem-admin/requirements.txt`.

---

## [2.1.1] - 2026-03-27

### Fixed

- **Event loop blocking during APNs delivery** — `send_notification` used a synchronous `httpx.Client` inside the async `receive_webhook` route handler, blocking FastAPI's event loop for the full APNs round-trip (up to 10 s per token). Converted to `httpx.AsyncClient` with `async`/`await` throughout `send_notification` and `send_to_all`.
- **Webhook accepts any non-empty secret** — `/webhook` checked only that `?secret=` was present, not that it matched any registered device; an unknown secret now returns HTTP 403 instead of HTTP 200 with `{"status": "no_devices"}`, preventing endpoint probing.

---

## [2.1.0] - 2026-03-26

### Added

- **BHNM API proxy** — catch-all `/{path}` route forwards all BHNM API requests from BeNeM through the middleware, enabling access to BHNM servers on private networks. Authenticated via `X-Proxy-Token` header; target server supplied per-request via `X-BHNM-Target` header.

### Fixed

- Proxy now returns a proper `Response` object to avoid FastAPI tuple serialisation error
- Proxy timeout increased to 60 s to accommodate slow BHNM responses
- `content-encoding` and `content-length` hop-by-hop headers stripped from proxied responses so Starlette correctly sets `Content-Length` from the decompressed body
- Proxy returns HTTP 504 on timeout and HTTP 502 on connection/request errors with descriptive messages

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
