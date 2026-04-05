# BeNeM PWA

React/TypeScript Progressive Web App for BHNM incident monitoring.
Targets Android via Web Push (future). iOS users are directed to the
native app via an in-app banner — Web Push is unreliable on iOS.

Part of the BeNeM monorepo. See `../CLAUDE.md` for cross-cutting rules
and `../shared/feature-spec.md` for the canonical feature list.

## v0.1.0 scope

- Incident List screen (read-only, 120s auto-refresh, pull-to-refresh, tap-to-detail stub)
- iOS redirect banner
- PWA manifest + service worker (offline scaffolding only — no data caching)

Deferred to later versions:
- Swipe ACK / UnACK (v0.1.1)
- Incident detail screen (v0.1.1)
- Settings screen (v0.1.1)
- Web Push subscription for Android (v0.2.0)

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

Without a real `VITE_BHNM_API_KEY`, the list shows mock fixture data so
you can still work on the UI. Append `?mock=1` to the URL to force mock
data even when a key is set.

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

- **Stack:** Vite 5 + React 18 + TypeScript strict + Tailwind v3 + vite-plugin-pwa + TanStack Query v5 + React Router v6.
- **Dev proxy:** `/bhnm/*` is forwarded to `VITE_MIDDLEWARE_BASE` (default `https://bhnm-apns.hurrikap.org`) with `changeOrigin: true`. This avoids CORS during development.
- **Production deployment / CORS:** not yet designed — see v0.1.1.
- **BHNM contract:** `POST /api/incident_api.php` with `pwd`/`method=getincidents` (form-urlencoded). The parser handles array-wrapped responses, `active_incidents`/`closed_incidents`, and multiple severity key names — mirroring the iOS client.

## Middleware coupling

The BHNM API key you set in `VITE_BHNM_API_KEY` must exist in the
deployed middleware's `servers.json`. The middleware proxy looks up the
target BHNM server by that key.

## Production hosting

The PWA is deployed at `https://benem.hurrikap.org` as a dedicated
`benem-pwa` container managed by `middleware/docker-compose.yml`. The
same Caddy instance that fronts the `bhnm-apns` push middleware
terminates TLS for both hostnames and same-origin-proxies
`/bhnm/*` on the PWA host to the middleware container — so the PWA
has no CORS dependency and shares no code with the middleware image.

First-time deploy checklist (run on the server, repo root):

1. `git pull`
2. Add `PWA_DOMAIN=benem.hurrikap.org` to `middleware/.env`
3. Create a DNS A/AAAA record for `benem.hurrikap.org` pointing at the server
4. Wait for DNS to propagate (`dig +short benem.hurrikap.org`)
5. `cd middleware && docker compose up -d` (Caddy will provision a Let's Encrypt cert automatically)
6. Visit `https://benem.hurrikap.org/settings` and enter your BHNM API key

Subsequent deploys are `./middleware/upgrade.sh`, which rebuilds the
`benem-pwa` image from the current `pwa/` source on every run.

The API key you enter in Settings is stored in your browser's
`localStorage` (scoped to `benem.hurrikap.org`) and is never sent
anywhere except BHNM via the middleware proxy.
