# BHNM PWA

React/TypeScript Progressive Web App (v0.8.0). Targets Android users via Web Push.
iOS users are directed to the native app for reliable push notifications.

> Part of the BeNeM monorepo. See `../CLAUDE.md` for cross-cutting rules,
> `../shared/feature-spec.md` for the canonical feature list, and
> `../shared/push-payload-spec.md` for the notification payload contract.

## Tech Stack

- **Framework:** React 19 + TypeScript
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
│   ├── components/                 # Shared UI (AppLayout, TabBar, RefreshRing, IOSRedirectBanner, ...)
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
2. Opens (or focuses) the PWA at `/incidents?id=<incident_id>` — **not** `/incident` (singular). Use the plural route; the incident list page handles the `id` query param and navigates to detail.
3. Focuses an existing tab if one is already open, otherwise opens a new window.

Payload contract: see `../shared/push-payload-spec.md`.

## Key Design Decisions

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

Push on iOS is unreliable (subscription expiry bug, no Time Sensitive
entitlement) and EU-regulatorily unstable. Do NOT position Web Push as
the primary alert channel for iOS users. Display a prominent banner to
iOS users recommending the native app for incident alerts. See
`../shared/DECISION.md` for the full rationale.

## Feature Spec

Refer to `../shared/feature-spec.md`. PWA-specific behaviour is marked there.
