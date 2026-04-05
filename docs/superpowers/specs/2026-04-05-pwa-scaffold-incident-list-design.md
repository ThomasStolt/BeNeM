# PWA v0.1.0 — Scaffold + Incident List

**Date:** 2026-04-05
**Status:** Design
**Scope:** Scaffold `pwa/` and implement the Incident List screen. Stop for review before further features.

## Goal

Stand up the BeNeM Progressive Web App as a new workspace under `pwa/`, and ship a first visible screen — the Incident List — wired to real BHNM data through the existing middleware proxy. This is the foundation for subsequent PWA features (Incident Detail, Web Push subscription for Android, Settings, etc.), all deferred to later iterations.

Out of scope for v0.1.0:
- Web Push (subscription, service worker push handler, VAPID setup)
- Incident Detail screen (route stub only)
- Swipe-to-ACK / UnACK (deferred to v0.1.1 — needs its own design for optimistic updates, error rollback, and ACK endpoint selection)
- Settings screen (config read from `.env.local` for now)
- Production deployment / CORS on middleware
- Additional middleware work — the existing BHNM proxy in `middleware/main.py` is sufficient

## Context

- The BeNeM monorepo contains `ios/` (shipped), `middleware/` (shipped), and an empty `pwa/` scaffold (`src/.gitkeep` only).
- `middleware/main.py` exposes a catch-all BHNM proxy (line 155) that looks up the target BHNM server by the `password` / `pwd` query/body parameter in `servers.json`. iOS already uses this; the PWA will too.
- No CORS headers are set on middleware today. For v0.1.0 this is fine: Vite's dev proxy sidesteps the browser's same-origin policy during development. Production deployment (same-origin via Caddy, or adding `CORSMiddleware` to FastAPI) is deferred.
- `shared/feature-spec.md` currently defines one feature: Incident List. The iOS version is shipped; the PWA version is "not yet implemented".

## Stack

| Concern | Choice | Rationale |
|---|---|---|
| Build tool | Vite 5 | Fast dev, first-class PWA plugin support |
| UI framework | React 18 + TypeScript (strict) | Required by task; matches future team expectations |
| Styling | Tailwind CSS v3 | Stable; v4 still maturing |
| PWA | `vite-plugin-pwa` (Workbox, `registerType: 'autoUpdate'`) | Generates service worker + manifest |
| Server state | TanStack Query v5 | Cache, auto-refresh interval, invalidation all map directly to the feature spec |
| Routing | React Router v6 | One route now, `/incident/:id` stub for the tap target |
| Tests | Vitest + `@testing-library/react` | Vite-native, fast |
| Config state | `localStorage` + a `useConfig()` hook | No global store needed for v0.1.0 |

No Redux / Zustand. No component library — Tailwind only. No icon library yet; inline SVG where needed.

## Directory layout

```
pwa/
├── index.html
├── package.json
├── tsconfig.json
├── tsconfig.node.json
├── vite.config.ts
├── tailwind.config.js
├── postcss.config.js
├── .env.example
├── .gitignore
├── README.md
├── public/
│   └── icons/                      # PWA icon placeholders
└── src/
    ├── main.tsx                    # React root, QueryClientProvider, BrowserRouter
    ├── App.tsx                     # Layout shell + routes + iOS banner
    ├── index.css                   # Tailwind directives
    ├── vite-env.d.ts
    ├── lib/
    │   ├── api/
    │   │   ├── client.ts           # fetch wrapper, base URL, error mapping
    │   │   ├── incidents.ts        # getIncidents()
    │   │   └── types.ts            # Incident, Severity, AlarmState
    │   ├── config.ts               # useConfig() — reads VITE_* env, optional localStorage override
    │   ├── platform.ts             # isIOS() user-agent detection
    │   └── mock/
    │       └── incidents.json      # Fallback data for ?mock=1 and empty-config state
    ├── features/
    │   └── incidents/
    │       ├── IncidentListScreen.tsx
    │       ├── IncidentRow.tsx
    │       ├── SeverityBadge.tsx
    │       ├── useIncidents.ts     # TanStack Query hook, 120s refetchInterval
    │       └── __tests__/
    │           └── IncidentListScreen.test.tsx
    └── components/
        ├── IOSRedirectBanner.tsx
        ├── PullToRefresh.tsx       # minimal touch-based gesture wrapper
        └── EmptyState.tsx
```

## Component & data flow

```
main.tsx
  └── QueryClientProvider
        └── BrowserRouter
              └── App
                    ├── IOSRedirectBanner (conditional on isIOS())
                    └── Routes
                          ├── "/"             → IncidentListScreen
                          └── "/incident/:id" → IncidentDetailStub
```

- `IncidentListScreen` calls `useIncidents()` (wraps `useQuery({ queryKey: ['incidents'], queryFn: getIncidents, refetchInterval: 120_000, refetchOnWindowFocus: true })`).
- `getIncidents()` calls `client.post('/fw/index.php?r=restful/', { method: 'getincidents', password, pin? })`, parses the array-wrapped BHNM response (`[{...}]`, per project memory), and returns `Incident[]`.
- `PullToRefresh` wraps the list and calls `queryClient.invalidateQueries({ queryKey: ['incidents'] })` on release.
- Each `IncidentRow` is a `<Link to={"/incident/" + id}>` — tap navigates to the stub.

### API client

- Base URL comes from `useConfig()`: in dev, requests go to `/bhnm/*` (Vite proxies to `VITE_MIDDLEWARE_BASE`); in prod the base URL is absolute (deferred).
- `password` (BHNM API key) and optional `pin` are injected into the request body by the client, mirroring iOS behaviour.
- Errors map to a small tagged union: `{ kind: 'network' | 'auth' | 'server' | 'parse', message: string }` so the UI can show appropriate empty states.

### Config

- `VITE_MIDDLEWARE_BASE` — e.g. `https://bhnm-apns.hurrikap.org`. Used only by `vite.config.ts` dev proxy.
- `VITE_BHNM_API_KEY` — the `password` sent with every request. Dev-only for v0.1.0; a Settings screen lands in v0.1.1.
- `VITE_BHNM_PIN` — optional.
- If no API key is configured, the list shows an `EmptyState` with a "Not configured" message pointing at `README.md`.
- `?mock=1` query param bypasses the real API and returns `mock/incidents.json` — useful for UI review before a BHNM instance is wired.

### Vite dev proxy

```ts
// vite.config.ts (excerpt)
server: {
  proxy: {
    '/bhnm': {
      target: process.env.VITE_MIDDLEWARE_BASE ?? 'https://bhnm-apns.hurrikap.org',
      changeOrigin: true,
      rewrite: (p) => p.replace(/^\/bhnm/, ''),
    },
  },
},
```

### iOS redirect banner

- `isIOS()` returns `/iPad|iPhone|iPod/.test(navigator.userAgent) && !window.MSStream`.
- Banner is a sticky top bar: "For reliable incident alerts, install the BeNeM iOS app." Dismissible per session (`sessionStorage` flag).
- App Store link is a placeholder `#` href with a `TODO` comment — to be replaced when the App Store listing is live.
- Banner exists to satisfy the hard rule in `pwa/CLAUDE.md`: never position Web Push as iOS's primary alert channel.

## Error handling

- Network errors → empty state "Could not reach BHNM. Retrying in 120s." with a manual retry button.
- Auth errors (HTTP 401/403) → empty state "Invalid API key. Check configuration."
- Parse errors (unexpected BHNM response shape) → empty state "Unexpected response from BHNM" + console log for debugging.
- No global error boundary in v0.1.0 — the list screen handles its own states. A global boundary can be added when there's a second screen.

## Testing

One smoke test in `__tests__/IncidentListScreen.test.tsx`:
- Renders `IncidentListScreen` with a mocked `useIncidents()` returning fixture data.
- Asserts a row is rendered for each mock incident.
- Asserts the severity badge renders for at least one known severity.

This is deliberately minimal: the goal is to prove the scaffold wires up React + TanStack Query + Testing Library correctly, not to exhaustively test logic that doesn't exist yet.

## Feature-spec update

`shared/feature-spec.md` → mark Incident List PWA section as `in-progress` and note: "v0.1.0: list only (read-only, 120s refresh, tap-to-detail-stub). v0.1.1: swipe ACK/UnACK + detail screen."

## Stop point

After the Incident List screen renders against either mock data or a real BHNM instance and the smoke test passes, **stop for user review** before moving on to Incident Detail, Settings, or Web Push work.

## Version

`package.json` → `"version": "0.1.0"`.

## Risks & open items

- **No App Store URL yet:** the iOS banner link is a placeholder. Must be fixed before public release, but acceptable during internal development.
- **No production deployment path:** this design does not specify how the PWA is hosted. Options (same-origin under Caddy alongside middleware, or a separate static host with CORS enabled on middleware) will be decided in a later spec.
- **Config in env vars is developer-only:** a real user-facing Settings screen is required before any non-developer can use the PWA. v0.1.1.
- **`servers.json` lookup coupling:** the middleware proxy routes by `password` matching an entry in `servers.json`. Whichever API key you put in `VITE_BHNM_API_KEY` must exist in the deployed middleware's `servers.json`. Documented in `pwa/README.md`.
