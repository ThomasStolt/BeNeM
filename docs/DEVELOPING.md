# BeNeM — Developer Guide

For people building or modifying BeNeM. If you are a BHNM administrator deploying it, you want
[`INSTALL.md`](INSTALL.md) instead.

## Requirements

**iOS app** — iOS 17.0+, Xcode 15+
**PWA** — Node.js 20+ and npm; a modern evergreen browser
**Middleware** — Docker / Docker Compose, or Python 3.11+ bare metal
**Both clients** — a running BHNM instance, minimum version **26.1.02**

## Clone

```bash
git clone https://github.com/ThomasStolt/BeNeM.git
cd BeNeM
```

## iOS app

```bash
open ios/BeNeM.xcodeproj
```

Then in Xcode:

1. Select the `BeNeM` target
2. Under **Signing & Capabilities**, select your Apple Developer Team
3. Adjust the Bundle Identifier if needed (default: `com.tstolt.benem`)
4. Select a simulator or your connected device, press ▶

Or use the build script:

```bash
cd ios
cp build.local.sh.example build.local.sh   # set BENEM_DEVICE_ID to your device UDID
./build_and_deploy.sh
```

`BeNeM/Secrets.swift` is gitignored and must be created before the app will build — see
[`../ios/SETUP.md`](../ios/SETUP.md). Its key must match the middleware's `BENEM_SECRET_KEY`.

> For corporate or self-signed certificate servers the app includes `NSAllowsArbitraryLoads` in its
> `Info.plist`. Review your ATS settings before submitting to the App Store.

## PWA

```bash
cd pwa
cp .env.example .env.local     # middleware URL and BHNM API key
npm install
npm run dev                    # dev server with hot reload and BHNM proxy
npm run build                  # typecheck + production build
npm test                       # Vitest
```

Without a real API key the list shows mock fixtures; append `?mock=1` to force them.
See [`../pwa/README.md`](../pwa/README.md) for architecture and commands.

## Middleware

```bash
cd middleware
cp .env.example .env
./check-env.sh                 # validates .env before you start anything
docker compose up -d
python -m pytest tests         # the whole middleware suite
```

### The admin portal suite needs its own virtualenv

`middleware/benem-admin` is a separate app with a separate suite, and **the documented command
does not work from a clean shell on macOS.** Homebrew's Python is an externally-managed
environment (PEP 668), so `pip install` refuses, and `pytest` then fails at collection with
`ModuleNotFoundError: No module named 'pyotp'`. Do **not** reach for `--break-system-packages`:
that writes into the interpreter the OS owns.

```bash
cd middleware/benem-admin
python3 -m venv .venv                       # or anywhere outside the repo
.venv/bin/pip install -r requirements-dev.txt
.venv/bin/python -m pytest                  # the admin suite
```

Verified 2026-09-15 on macOS with Homebrew Python 3.14. Filed rather than fixed: the failure is
environmental, not a bug in the suite, and it costs the next person twenty minutes to rediscover.

`middleware/README.md` documents every environment variable and endpoint;
`middleware/CLAUDE.md` covers design decisions, the cache loops and the upgrade runbook.

## Repository Layout

This is a monorepo with four top-level subprojects:

| Path | Purpose |
|---|---|
| [`ios/`](../ios/) | Native Swift/SwiftUI iOS app. Primary platform, distributed via App Store / TestFlight. |
| [`pwa/`](../pwa/) | React/TypeScript Progressive Web App targeting Android via Web Push, and desktop browsers as a web dashboard. |
| [`middleware/`](../middleware/) | Python/FastAPI service. Ingests BHNM webhooks and delivers push notifications to iOS (APNs) and Android (Web Push). |
| [`shared/`](../shared/) | Specifications and documentation shared between clients — feature spec, push payload contract, API reference. |

The full platform strategy (why native iOS + PWA Android, not a single cross-platform app) is documented in [`shared/DECISION.md`](../shared/DECISION.md).

### The architecture diagram in `docs/`

`docs/benem-runtime-architecture.html` is a **generated 802 KB single-file page**, tracked
deliberately. It is the interactive runtime map the README links to, and it is served straight from
GitHub Pages (this repo has Pages enabled on `main` + `/docs`, so anything in `docs/` is public at
`https://thomasstolt.github.io/BeNeM/<file>`). A `.html` blob linked on github.com renders as
source, not as a page — Pages is the reason the README link works at all. It is large because the
page inlines its own CSS, JS and fonts; do not "optimise" it by hand.

**Do not edit the HTML.** The source of truth is
[`docs/benem-runtime-architecture.json`](benem-runtime-architecture.json) (~10 KB). Edit that, then
regenerate:

```bash
node ~/.agents/skills/archify/bin/archify.mjs deliver architecture \
  docs/benem-runtime-architecture.json docs/benem-runtime-architecture.html \
  --quality showcase --repo-root . --json
```

Then re-shoot the two README thumbnails (`docs/architecture-light.png`, `-dark.png`) with headless
Chrome against `docs/benem-runtime-architecture.html?embed=1&theme=light` and `…&theme=dark`
(`--force-device-scale-factor=2 --window-size=1400,506`, then `sips -c 980 2800`).

Several components in the JSON pin `sources` to a commit SHA. That SHA goes stale as the repo
moves, and `--repo-root` verification fails if a referenced path or line range disappears — update
it when files move.


## Project Structure

```
BeNeM/
├── ios/                       # Native Swift/SwiftUI iOS app
│   ├── BeNeM/
│   │   ├── Models/            # Incident, Device, Group, IncidentDetail models
│   │   ├── Services/          # API client, URL building, deep-link handler
│   │   ├── ViewModels/        # List, Detail, Tactical view models
│   │   ├── Views/             # SwiftUI views (Dashboard, Incidents, Devices, Settings, …)
│   │   └── BeNeMApp.swift     # App entry point + URL scheme handler
│   ├── BeNeM.xcodeproj
│   ├── build_and_deploy.sh
│   └── CLAUDE.md              # iOS-specific context
│
├── pwa/                       # React/TypeScript Progressive Web App (v0.9.0)
│   ├── src/                   # Components, pages, API client, service worker
│   └── CLAUDE.md              # PWA-specific context
│
├── middleware/                # Python/FastAPI push middleware (formerly bhnm-apns)
│   ├── main.py                # FastAPI app, /register /webhook /health endpoints
│   ├── apns.py                # APNs (iOS) delivery — JWT + HTTP/2
│   ├── database.py            # SQLite token store with per-device active_secret routing
│   ├── docker-compose.yml
│   └── CLAUDE.md              # Middleware context + design decisions
│
├── shared/                    # Specs shared between clients (source of truth)
│   ├── DECISION.md            # Platform strategy record
│   ├── feature-spec.md        # Canonical feature list, per-platform notes
│   ├── push-payload-spec.md   # Push notification payload contract
│   └── BHNM_API_REFERENCE.md  # Full BHNM API reference
│
└── CLAUDE.md                  # Monorepo-wide context
```

> **Note on class names:** Swift types use the legacy `Netreo` prefix (e.g. `NetreoAPIService`, `NetreoIncident`) as they predate the product rebrand. AppStorage keys (`netreo_base_url`, `netreo_api_key`, etc.) are also kept unchanged to preserve existing user settings.

## API Compatibility

Both clients speak to the same BHNM server using a mix of legacy PHP endpoints and RESTful endpoints:

| Action | Method | Endpoint |
|---|---|---|
| List incidents | POST | `/api/incident_api.php` (`method=getincidents`) |
| Incident detail | POST | `/api/incident_api.php` (`method=getincidentdetail`) |
| Acknowledge | POST | `/fw/index.php?r=restful/incident/acknowledge` |
| Unacknowledge | POST | `/fw/index.php?r=restful/incident/unacknowledge` |
| List devices | POST | `/fw/index.php?r=restful/devices/list` |
| Tactical overview (H/S/T) | POST | `/fw/index.php?r=restful/tactical-overview/data` |
| Find device by name | POST | `/fw/index.php?r=restful/devices/find` |
| Performance categories | POST | `/fw/index.php?r=restful/devices/performance-category` |
| Performance instances | POST | `/fw/index.php?r=restful/devices/performance-instance-per-category` |
| Time-series metrics | POST | `/fw/index.php?r=restful/devices/timeseries-metrics` |

See [`shared/BHNM_API_REFERENCE.md`](../shared/BHNM_API_REFERENCE.md) for the full reference.

The tactical overview endpoint accepts a `grouping_type` body parameter (`category`, `site`, or `app` for Business Workflows) and returns pre-aggregated host, service, and threshold counts per group directly from BHNM's monitoring core — the same data source as BHNM's own web dashboard.

> **Note on alarm status:** H/S/T counts come directly from `restful/tactical-overview/data`, which returns `host_*_count`, `service_*_count`, and `threshold_*_count` fields per group. Status values map to badge colors as follows: `ok` → green, `ack` → blue, `warn` → yellow, `un` (unvalidated) → orange, `crit` → red.

## Versioning

Releases follow [Semantic Versioning](https://semver.org): `MAJOR.MINOR.PATCH`. Each subproject versions independently.

```bash
# iOS app — bumps MARKETING_VERSION + CURRENT_PROJECT_VERSION via xcrun agvtool
cd ios
./scripts/bump_version.sh patch   # 1.1.0 → 1.1.1
./scripts/bump_version.sh minor   # 1.1.0 → 1.2.0
./scripts/bump_version.sh major   # 1.1.0 → 2.0.0
```

See [`ios/CHANGELOG.md`](../ios/CHANGELOG.md) and [`middleware/CHANGELOG.md`](../middleware/CHANGELOG.md) for per-subproject release histories.

