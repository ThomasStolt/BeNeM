# BeNeM — Mobile Clients for BMC Helix Network Management

An open-source mobile application for **BMC Helix Network Management (BHNM)**. This is an independent project — it is not affiliated with, endorsed, guaranteed, or supported by BMC Software. BMC, Helix, and BHNM are trademarks of BMC Software, Inc. If you find a bug or have a feature request, contributions are welcome!

This repository provides **two client apps** and a companion middleware:

| App | Platform | Distribution |
|---|---|---|
| **Native iOS app** (Swift/SwiftUI) | iPhone, iPad | App Store / TestFlight |
| **Progressive Web App** (React/TypeScript) | Android, Desktop browsers | Install from `https://benem.hurrikap.org` — "Add to Home Screen" |

Both apps share the same feature set and connect to the same BHNM servers via a lightweight **push notification middleware** (Python/FastAPI) that bridges BHNM webhooks to Apple Push Notification service (APNs) for iOS and VAPID Web Push for Android.

**When a new incident is created in BHNM, a push notification is instantly delivered to every registered device** — no polling, no delay. Tap the notification to jump straight to the incident detail.

> **Note:** BMC Helix Network Management (BHNM) was formerly known as **Netreo**. Internal code identifiers (class names, AppStorage keys) still use the legacy `Netreo` prefix for backwards compatibility and will be migrated in a future release.

## Repository Layout

This is a monorepo with four top-level subprojects:

| Path | Purpose |
|---|---|
| [`ios/`](ios/) | Native Swift/SwiftUI iOS app. Primary platform, distributed via App Store / TestFlight. |
| [`pwa/`](pwa/) | React/TypeScript Progressive Web App targeting Android via Web Push, and desktop browsers as a web dashboard. |
| [`middleware/`](middleware/) | Python/FastAPI service. Ingests BHNM webhooks and delivers push notifications to iOS (APNs) and Android (Web Push). |
| [`shared/`](shared/) | Specifications and documentation shared between clients — feature spec, push payload contract, API reference. |

The full platform strategy (why native iOS + PWA Android, not a single cross-platform app) is documented in [`shared/DECISION.md`](shared/DECISION.md).

## Demo

Here are a few examples of how the iOS app looks and feels. You can see the home dashboard, active incidents, acknowledgement of incidents, device list and a device performance view. The PWA mirrors the same features with a browser-native UI.

<div align="center">
  <img src="ios/images/demo1.gif" width="260" alt="Demo part 1 — dashboard and incidents">
  &emsp;
  <img src="ios/images/demo2.gif" width="260" alt="Demo part 2 — device detail and performance charts">
  &emsp;
  <img src="ios/images/demo3.gif" width="260" alt="Demo part 3 — tactical overview and settings">
</div>

## Features

Features are defined once in [`shared/feature-spec.md`](shared/feature-spec.md) and implemented on both platforms unless explicitly marked platform-specific.

- **Push Notifications** — instant incident alerts delivered the moment a new incident is raised in BHNM; tap to navigate directly to the incident detail screen. iOS uses APNs with Time Sensitive entitlement; Android uses VAPID Web Push via the installed PWA.
- **Dashboard (Home)** — at-a-glance summary with active incident count, total device count, an animated incident ticker (open incidents only), and HOSTS / SERVICES / THRESHOLDS / ANOMALIES alarm summaries with drill-down links to Categories, Sites, and Business Workflows
- **Categories / Sites / Business Workflows** — group lists showing each group's device count and color-coded alarm status rows (H / S / T / A) across Green / Blue / Yellow / Orange / Red; alternating row backgrounds for readability; filter to show only groups with active alarms; empty group names shown as "Unknown"
- **Incident List** — live view of active, acknowledged, and closed incidents with severity badges and per-incident alarm counts; sorted newest-first by Incident ID
- **Acknowledge / Unacknowledge** — swipe right to ACK, swipe left to UnACK on both platforms, with instant local status update
- **Incident Detail** — primary alarms, related alarms, and the full incident state log
- **Device Detail** — tap any device for a full detail view with a 3-column header card (icon, device info, mini latency chart), active incidents, performance metric charts (CPU, memory, disk, interfaces, latency), and network interface status
- **CPU Cores chart** — combined multi-line chart showing up to 4 CPU cores with distinct colors, actual BHNM core names, and auto-scaled Y axis
- **Performance charts on-demand** — metric cards in Device Detail fetch and render their time-series chart only when expanded
- **Incident Ticker** — animated banner on the Dashboard cycles through the latest open incidents; tap to navigate directly to the detail screen
- **Filters** — filter incidents by severity and status; filter tactical groups to show only those with any non-green alarms (hosts, services, thresholds, or anomalies)
- **Named connections** — save multiple BHNM servers and switch between them via a connection picker in Settings; connection test shows a green dot on success, no popup
- **QR code scanner** — scan a `benem://` configuration QR code directly from Settings to add a new server; generated by the **benem-admin** portal (part of [`middleware/`](middleware/))
- **URL scheme import** — import a server connection via `benem://configure?url=…&key=…` deep link (QR code, MDM profile, or share sheet)
- **Auto-refresh** — data refreshes automatically every 120 seconds with a visible countdown ring; tap the ring to refresh immediately
- **Auto-retry** — all screens automatically retry the connection 15 seconds after a network failure
- **Pull-to-refresh** — manual refresh at any time by pulling down any list
- **Connection Test** — built-in connectivity test with detailed diagnostics; green dot on success, red dot + alert on failure
- **Multiple API versions** — supports Legacy (PHP), API v1, API v2, and OpenAPI 3.0 endpoints

Here are two screenshots from the iOS app — the Dashboard with its alarm summary cards (left), and the Active Incidents dashboard with severity and alarm indicators (right):

<div align="center">
  <img src="ios/images/BHNM%20Home%20Screen.jpeg" alt="Dashboard — alarm summaries and incident ticker" width="240">
  &emsp;&emsp;&emsp;&emsp;&emsp;&emsp;
  <img src="ios/images/BHNM_Incidents.jpeg" alt="Active Incidents — severity badges and alarm indicators" width="240">
</div>

## Requirements

**iOS app**
- iOS 16.0 or later
- Xcode 15 or later

**PWA**
- A modern evergreen browser (Chrome, Edge, Firefox, Safari)
- Android 13 or later for full Web Push support (installed as a home-screen PWA)
- Node.js 20+ and npm for local development

**Middleware**
- Docker / Docker Compose (recommended), or Python 3.11+ for bare-metal installs

**Both clients**
- A running BHNM instance (on-premise or SaaS), minimum version **26.1.02**

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/thomasstolt/BeNeM.git
cd BeNeM
```

### 2. iOS app

```bash
open ios/BeNeM.xcodeproj
```

Then in Xcode:

1. Select the `BeNeM` target
2. Under **Signing & Capabilities**, select your Apple Developer Team
3. Adjust the Bundle Identifier if needed (default: `com.tstolt.benem`)
4. Select a simulator or your connected device, press ▶

Alternatively, use the included build script:

```bash
cd ios
cp build.local.sh.example build.local.sh
# Edit build.local.sh — set BENEM_DEVICE_ID to your device's UDID
./build_and_deploy.sh
```

> **Note:** For corporate or self-signed certificate servers the app includes `NSAllowsArbitraryLoads` in its `Info.plist`. Review and adjust your ATS settings before submitting to the App Store.

### 3. PWA

```bash
cd pwa
npm install
npm run dev            # local development server
npm run build          # production build
```

Deploy the contents of `pwa/dist/` to any static-file host (Cloudflare Pages, Netlify, Vercel, a plain nginx, etc.). Open the deployed URL on an Android device and tap **Add to Home screen** to install. The first launch will prompt for notification permission — accept to enable Web Push incident alerts.

> **iOS users:** The PWA is available in the browser but **push notifications are not reliable on iOS Web Push** (subscription expiry, no Time Sensitive entitlement). iOS users are directed to install the native app instead. See [`shared/DECISION.md`](shared/DECISION.md) for the full rationale.

### 4. Middleware

```bash
cd middleware
cp .env.example .env
# Edit .env — APNs .p8 key (base64), VAPID keys, webhook secret, domain
docker compose up -d
```

See [`middleware/CLAUDE.md`](middleware/CLAUDE.md) for deployment details, per-device `active_secret` routing, and the `/register` / `/webhook` / `/health` endpoints.

## Configuration

### Onboarding (recommended)

The fastest way to get a user connected is for an administrator to send them a provisioning link generated by the **benem-admin** portal (part of [`middleware/`](middleware/)). The portal produces a `benem://configure?…` URL that carries the BHNM server URL, API key, optional PIN/LicenseID, and push middleware settings — all sensitive fields are AES-256-GCM encrypted inside the URL.

Administrators can share the link in two ways:

- **QR code** — the user opens the app's built-in scanner (**Settings → Scan QR Code**) and points the camera at the code. On iOS, the scanner is a full-screen camera view; on the Android PWA, it uses the browser's Barcode Detection API (or a WebRTC-based fallback for browsers that don't support it natively).
- **`benem://` deep link** — sent via email, chat, or MDM profile. Tapping the link on iOS opens the native app directly; on Android, tapping the link opens the installed PWA via its registered `web+benem` protocol handler (or, if not yet installed, the browser with a prompt to install first). Either platform then decrypts the payload, applies the settings, and is ready to use immediately.

This is the supported happy path — end users should never need to type a base URL or API key by hand.

### Manual configuration

If you need to configure by hand, open **Settings** on either client and enter:

| Field | Description |
|---|---|
| Base URL | Your BHNM server URL, e.g. `https://bhnm.example.com` |
| API Key | Your BHNM API key |
| PIN/LicenseID | Only required for SaaS deployments |
| ACK User | Username recorded when acknowledging incidents |
| API Version | Not used |
| Timeout | Request timeout in seconds (default: 30 s) |
| Retry Count | Number of retries on failure (default: 3) |

Tap the **Test** button to verify your settings. A green dot confirms the connection was successful and saves the server automatically; a red dot shows a diagnostic alert.

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
├── pwa/                       # React/TypeScript Progressive Web App
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
| Incident detail | GET | `/api/incident_api.php` (`method=getincidentdetail`) |
| Acknowledge | POST | `/fw/index.php?r=restful/incident/acknowledge` |
| Unacknowledge | POST | `/fw/index.php?r=restful/incident/unacknowledge` |
| List devices | POST | `/fw/index.php?r=restful/devices/list` |
| Tactical overview (H/S/T) | POST | `/fw/index.php?r=restful/tactical-overview/data` |
| Find device by name | POST | `/fw/index.php?r=restful/devices/find` |
| Performance categories | POST | `/fw/index.php?r=restful/devices/performance-category` |
| Performance instances | POST | `/fw/index.php?r=restful/devices/performance-instance-per-category` |
| Time-series metrics | POST | `/fw/index.php?r=restful/devices/timeseries-metrics` |

See [`shared/BHNM_API_REFERENCE.md`](shared/BHNM_API_REFERENCE.md) for the full reference.

The tactical overview endpoint accepts a `grouping_type` body parameter (`category`, `site`, or `app` for Business Workflows) and returns pre-aggregated host, service, and threshold counts per group directly from BHNM's monitoring core — the same data source as BHNM's own web dashboard.

> **Note on alarm status:** H/S/T counts come directly from `restful/tactical-overview/data`, which returns `host_*_count`, `service_*_count`, and `threshold_*_count` fields per group. Status values map to badge colors as follows: `ok` → green, `ack` → blue, `warn` → yellow, `un` (unvalidated) → orange, `crit` → red.

## Push Notifications

BeNeM delivers real-time push notifications for new incidents on **both platforms** via a single companion middleware (see [`middleware/`](middleware/)) that bridges BHNM's webhook output to the appropriate push service per client:

- **iOS** — Apple Push Notification service (APNs) using a `.p8` Auth Key and JWT-signed HTTP/2 requests
- **Android PWA** — VAPID-signed Web Push via the browser's Service Worker

![BeNeM system architecture: iOS and Android/PWA clients connect via HTTPS to the middleware, which caches incidents, proxies API calls to BHNM, and delivers push notifications via APNs (iOS) and Web Push (Android)](shared/BHNM%20Mobile%20App%20-%20Detailed%20Architecture.png)

When a new incident is raised in BHNM, a webhook fires to the middleware. The middleware authenticates the request using a per-device `active_secret` (each BHNM server has its own webhook secret), looks up all registered devices authorised for that secret, and fans out the notification via APNs or Web Push. Tapping the notification navigates directly to the incident detail screen — even from a cold launch.

The middleware URL and shared secret are configurable in **Settings → Push Notifications** on both clients and can also be provisioned via the `benem://` deep-link URL scheme (QR code, MDM profile, or share sheet).

The payload contract is defined in [`shared/push-payload-spec.md`](shared/push-payload-spec.md) and is the source of truth for both producer and consumers.

## Versioning

Releases follow [Semantic Versioning](https://semver.org): `MAJOR.MINOR.PATCH`. Each subproject versions independently.

```bash
# iOS app — bumps MARKETING_VERSION + CURRENT_PROJECT_VERSION via xcrun agvtool
cd ios
./scripts/bump_version.sh patch   # 1.1.0 → 1.1.1
./scripts/bump_version.sh minor   # 1.1.0 → 1.2.0
./scripts/bump_version.sh major   # 1.1.0 → 2.0.0
```

See [`ios/CHANGELOG.md`](ios/CHANGELOG.md) and [`middleware/CHANGELOG.md`](middleware/CHANGELOG.md) for per-subproject release histories.

## License

MIT — see [LICENSE](LICENSE) for details.
