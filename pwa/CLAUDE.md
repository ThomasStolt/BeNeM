# BHNM PWA

React/TypeScript Progressive Web App. Targets Android users via Web Push.
iOS users are directed to the native app for reliable push notifications.

> Part of the BeNeM monorepo. See `../CLAUDE.md` for cross-cutting rules,
> `../shared/feature-spec.md` for the canonical feature list, and
> `../shared/push-payload-spec.md` for the notification payload contract.

## Tech Stack

- **Framework:** React 18.3 + TypeScript
- **Build:** Vite
- **Testing:** Vitest
- **Push:** Web Push (VAPID) via `../middleware/`
- **Container:** Nginx (static files), proxied behind Caddy

## Project Structure

```
pwa/
├── src/
│   ├── main.tsx                    # Entry point, router, service worker registration
│   ├── App.tsx                     # Top-level app shell
│   ├── sw.ts                       # Service worker: Web Push handler + notificationclick routing
│   ├── features/
│   │   ├── dashboard/              # Home view
│   │   ├── incidents/              # Incident list + detail (deep-link target)
│   │   ├── devices/                # Device list + detail
│   │   ├── tactical/               # Category / Site / Business Workflow overviews
│   │   ├── performance/            # Time-series metric charts
│   │   ├── scanner/                # QR scanner for benem:// URLs
│   │   └── settings/               # Server config, push registration
│   ├── components/                 # Shared UI (AppHeader, TabBar, UpdatedAt, ConnectionBadge, StateBadge, ...)
│   └── lib/
│       ├── api/                    # BHNM API client
│       ├── serverStorage.ts        # Sync storage API backed by in-memory cache
│       ├── storage-crypto.ts       # AES-256-GCM encryption for sensitive fields
│       ├── pushRegistration.ts     # Web Push subscribe / register flow
│       ├── platform.ts             # iOS / Android / desktop detection
│       ├── qr-parser.ts            # benem:// URL parsing + decryption
│       └── crypto.ts               # Web Crypto wrappers (PBKDF2, AES-GCM)
├── public/icons/                   # PWA icons
├── nginx.conf                      # Static file server + security headers
└── Dockerfile
```

## Push Notification Handling

Web Push payload arrives at `src/sw.ts`. On `notificationclick`:

1. Reads `incident_id` from the notification's `data` payload
2. Focuses an existing tab if one is already open, otherwise opens a new window.
3. Posts `{ type: 'navigate', url: '/incidents/<incident_id>' }` to the client; `App.tsx` reads `event.data.url` and routes to the `/incidents/:id` detail view. The message key is `url` (not `path`), and the route is the **plural** path param `/incidents/:id` — not `/incident` (singular) and not a `?id=` query param.

Payload contract: see `../shared/push-payload-spec.md`.

## Key Design Decisions

### Unified App Header (`AppHeader`)

All four main screens (Home, Incidents, Devices, Settings) use the shared `AppHeader` component (`src/components/AppHeader.tsx`). It accepts `title`, `isLoading`, `isError`, `dataUpdatedAt`, and `onRefresh` props and internally calls `useConfig()` to read `serverName` and `isConfigured`. Connection status is derived purely from props:

- `!isConfigured` → `'disconnected'`
- `isLoading` → `'checking'`
- `isError` → `'disconnected'`
- `dataUpdatedAt > 0` → `'connected'`
- otherwise → `'unknown'`

Settings passes no `dataUpdatedAt` — the control is hidden and replaced by a same-width spacer.

### `Updated HH:MM` replaced the countdown ring (0.19.0)

`UpdatedAt` (`src/components/UpdatedAt.tsx`) states when the data was last confirmed and offers a refresh control. `RefreshRing` and `RefreshCountdown` are **deleted**.

Removing the countdown is a truthfulness fix, not a cosmetic one. **A countdown is a promise that something happens at zero.** Under webhook mode nothing does — the next scheduled reconciliation is 24 hours away — so the ring was counting down to nothing, which is a green affordance asserting a claim nobody had checked. `Updated HH:MM` states a fact the app can date.

The refresh control and the foreground resume both call `POST /api/v1/incidents/refresh` (middleware 2.20.0): one `getincidents`, single-flight, at most one per server per 30 s, no per-incident detail call. **The rate limit lives server-side and only server-side** — there is deliberately no client-side staleness check to go with it, which is what makes "one user's refresh serves everyone on that server" true rather than approximately true.

### The incident list filter (0.19.0)

Five pills — TOTL / OPEN / ACKD / CLRD / CLSD — plus search. Definitions live in ONE place, `src/features/incidents/pills.ts`, and the Home tile calls the same `pillCounts()` the pill row does, so the number on Home and the number on the pill agree by construction. See `../shared/feature-spec.md`.

### Incident Detail Data

`IncidentDetailScreen` always calls `useIncidentDetail(id)` on mount to load full incident data from `getincidentdetail`. The list-level `useIncidents()` cache provides instant basic fields (displayId, status) while the detail fetch is in-flight.

`IncidentRow` calls `useIncidentDetail(id, { enabled: alarmCounts === null })` to lazily load alarm counts when the middleware cache is cold. React Query caches the result for 60 s, so revisiting an incident detail is free.

### localStorage Encryption
Sensitive fields (`apiKey`, `pin`, `pushWebhookSecret`) are encrypted at rest
in localStorage using AES-256-GCM via the Web Crypto API. Key derivation uses
PBKDF2 (100K iterations, SHA-256) seeded with `location.origin`. Encrypted
values are prefixed with `$enc$` for migration detection. Non-sensitive fields
remain plaintext for debuggability.

- `src/lib/storage-crypto.ts` — encrypt/decrypt helpers
- `src/lib/serverStorage.ts` — sync API backed by an in-memory cache; async
  `initStorage()` decrypts on startup and migrates any plaintext secrets

### Security Headers
Nginx (`nginx.conf`) sets `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`,
and `Referrer-Policy`. Caddy adds HSTS and CSP on top.

## iOS Caveat

Push on iOS is unreliable (subscriptions silently expire on iOS WebKit, no
background sync) and EU-regulatorily unstable. Do NOT position Web Push as
the primary alert channel for iOS users. Display a prominent banner to
iOS users recommending the native app for incident alerts. See
`../shared/DECISION.md` for the full rationale.

## Feature Spec

Refer to `../shared/feature-spec.md`. PWA-specific behaviour is marked there.
