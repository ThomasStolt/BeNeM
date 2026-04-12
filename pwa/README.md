# BHNM PWA

React/TypeScript Progressive Web App for BMC Helix Network Management (BHNM) incident monitoring. Targets Android via Web Push. iOS users are directed to the native app via an in-app banner — Web Push is unreliable on iOS.

Part of the BeNeM monorepo. See `../CLAUDE.md` for cross-cutting rules and `../shared/feature-spec.md` for the canonical feature list.

## Current Version: 0.9.0

### What's New in v0.9.0

- **Incident detail iOS parity** — `IncidentDetailScreen` rebuilt to match the iOS app exactly:
  - Calls `getincidentdetail` on mount to load full incident data
  - **Status section** — icon ACK/UnACK button (✓ / ↩), `StatusBadge`, and all five alarm colour counts (green / blue / yellow / orange / red)
  - **Incident Info card** — ID, title, device, IP, alert type, created timestamp, verbose duration (`Xd Xh Xm Xs`), and ACK details when acknowledged
  - **Primary Alarms card** — state badge · type · name · HTML-stripped output · timestamp; hidden when empty
  - **Related Alarms card** — same structure; hidden when empty
  - **Incident State Log card** — state badge · timestamp · username · comment; hidden when empty
  - New `StateBadge` component maps raw alarm/log state strings to coloured pills (distinct from the three-state `StatusBadge` used on list rows)
  - New `useIncidentDetail` React Query hook (60 s stale time, query key `['incidentDetail', id]`)
- **Incident duration fix** — list rows previously always showed "now"; `startTime` field lookup now covers `incident_open_time` and `open_time` in addition to `start_time`
- **Alarm badge cold-cache fallback** — list rows where `alarmCounts` is null (middleware cache cold) lazily fetch counts via `getincidentdetail` per row and show animated shimmer placeholders while loading
- **Unified app header** — all four main screens (Home, Incidents, Devices, Settings) share the same `AppHeader` component: connection-status badge (left) · B-icon + screen title + server name (centre) · refresh ring (right)
- **RefreshRing countdown** — the circular refresh ring grows from 28 px to 40 px and displays an M:SS countdown centred inside (e.g. `1:18`, `0:45`, `2:00`)

### Previous Versions

- **v0.8.0** — Device view iOS alignment (device type icons, `DeviceRow` redesign, `DeviceDetailScreen` iOS parity, HEALTHY count, maintenance window improvements, SaaS compatibility)
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
