# BHNM PWA

React/TypeScript Progressive Web App for BMC Helix Network Management (BHNM) incident monitoring. Targets Android via Web Push. iOS users are directed to the native app via an in-app banner — Web Push is unreliable on iOS.

Part of the BeNeM monorepo. See `../CLAUDE.md` for cross-cutting rules and `../shared/feature-spec.md` for the canonical feature list.

## Current Version: 0.8.0

### What's New in v0.8.0

- **Device view iOS alignment (Phase 1)** — device list rows and detail screen now match the iOS native app:
  - Device type icons (Linux/Tux, Windows, Router, Switch) in `shared/icons/` as canonical SVG assets; `DeviceTypeIcon` component colours the icon background by device status
  - `DeviceRow` redesign — type icon on the left, alarm badges (green/blue/yellow/orange/red matching incident cards) on the right, scrolling incident ticker below the badges at constant speed
  - `DeviceDetailScreen` — centred device name + IP as screen title; iOS-style header card (icon · category/site/status · latency mini chart); alarm summary bar (HEALTHY / ACK / WARNING / CRITICAL, greyed out when zero); collapsible "Host Information" (closed by default) and "Current Issues" sections with severity-badged incident table
- **HEALTHY count** — computed per device as `thresholds + ok_service_checks − active_incidents`. Threshold counts fetched via a new middleware cache endpoint (`GET /api/v1/threshold-counts`) — the raw CSV is parsed server-side once per refresh interval rather than in every browser client
- **Maintenance window improvements** — auto-generated timestamp prefix is read-only; 255-character total limit enforced in the UI
- **SaaS compatibility** — PHP 8+ BHNM servers return `dev_index`, `category`, `site`, and other fields as integers; the PWA parser now accepts both integers and strings so performance charts and category/site labels work correctly on SaaS servers

### Previous Versions

- **v0.7.0** — iOS-style Dashboard, Settings iOS parity, QR scanning fixes, tab bar on all screens, app icon, error boundary, proxy auth
- **v0.6.0** — Performance charts, QR server onboarding, Web Push, localStorage encryption
- **v0.5.0** — Inline performance charts in Device Detail with Recharts
- **v0.4.0** — Device list, device detail, tactical drill-down views
- **v0.3.0** — Dashboard, multi-server management, tab bar navigation
- **v0.2.0** — Web Push notifications via VAPID
- **v0.1.0** — Incident list, iOS redirect banner, PWA manifest

## Platforms

| Platform | How to Use |
|---|---|
| **Android** | Open `https://benem.hurrikap.org` in Chrome, tap "Add to Home Screen" to install as PWA. Push notifications via Web Push. |
| **Desktop** | Open the same URL in any modern browser for a web dashboard. |
| **iOS** | The PWA works in Safari but push is unreliable. An in-app banner directs iOS users to install the native app from the App Store instead. |

## Prerequisites

- Node 20+
- `npm`
- A reachable BeNeM middleware instance with an entry for your BHNM server in `servers.json`

## Setup

```bash
cd pwa
cp .env.example .env.local
# Edit .env.local with your middleware URL and BHNM API key
npm install
npm run dev
```

Without a real API key, the list shows mock fixture data so you can still work on the UI. Append `?mock=1` to the URL to force mock data even when a key is set.

## Commands

| Command | Purpose |
|---|---|
| `npm run dev` | Vite dev server with hot reload and BHNM proxy |
| `npm run build` | TypeScript typecheck + production build |
| `npm run preview` | Serve `dist/` locally |
| `npm test` | Run Vitest once |
| `npm run test:watch` | Vitest in watch mode |
| `npm run typecheck` | TypeScript check only |

## Architecture

- **Stack:** Vite 5 + React 19 + TypeScript strict + Tailwind v3 + vite-plugin-pwa + TanStack Query v5 + React Router v6
- **Dev proxy:** `/bhnm/*` is forwarded to `VITE_MIDDLEWARE_BASE` (default `https://bhnm-apns.hurrikap.org`) with `changeOrigin: true`. This avoids CORS during development.
- **Production:** The PWA is deployed as a Docker container (nginx serving static files) behind Caddy, which same-origin-proxies `/bhnm/*` to the middleware container.
- **QR Encryption:** The `VITE_QR_ENCRYPTION_KEY` build env var is mapped from `BENEM_SECRET_KEY` in the middleware `.env` via a Docker build arg.

## Production Hosting

The PWA is deployed at `https://benem.hurrikap.org` as a dedicated `benem-pwa` container managed by `middleware/docker-compose.yml`. The same Caddy instance that fronts the middleware terminates TLS for both hostnames and same-origin-proxies `/bhnm/*` on the PWA host to the middleware container.

Deploy with `./upgrade.sh` from the middleware directory. The smart rebuild only rebuilds containers with changed files.
