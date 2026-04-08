# BHNM PWA

React/TypeScript Progressive Web App for BMC Helix Network Management (BHNM) incident monitoring. Targets Android via Web Push. iOS users are directed to the native app via an in-app banner — Web Push is unreliable on iOS.

Part of the BeNeM monorepo. See `../CLAUDE.md` for cross-cutting rules and `../shared/feature-spec.md` for the canonical feature list.

## Current Version: 0.7.0

### What's New in v0.7.0

- **iOS-style Dashboard** — summary cards (Active Incidents + Total Devices), step-through incident ticker with slide animation and page dots, iOS-style heat map status cards, full-width drill-down rows with icons, chain-link connection badge, circular refresh ring
- **Settings iOS Parity** — QR-scanned servers lock fields to read-only (except Server Name and Push toggle), added User Name, BHNM URL, and Middleware URL fields, single save-with-test button, server switch confirmation dialog, delete button
- **QR Scanning Fixes** — deferred scanner callback to prevent React crash, proper encryption key from BENEM_SECRET_KEY, duplicate detection by Server Name + BHNM URL + User Name
- **Tab Bar on All Screens** — Settings added as 4th tab, persistent bottom navigation everywhere
- **App Icon** — iOS app icon with handwritten "PWA" badge (Marker Felt)
- **Error Boundary** — catches React render crashes and shows a reload prompt instead of a blank screen
- **Proxy Auth** — all API calls now send X-Proxy-Token header for middleware authentication

### Previous Versions

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
