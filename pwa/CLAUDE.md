# BHNM PWA

React/TypeScript Progressive Web App (v0.7.0). Targets Android users via Web Push.
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
