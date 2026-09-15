# BeNeM Monorepo

BeNeM is a network monitoring and incident alerting app built on top of
**BMC Helix Network Management (BHNM)**. Its primary function is delivering
timely, reliable push notifications to engineers when incidents occur.

> **Naming note:** BHNM was formerly known as **Netreo**. Swift type names
> (`NetreoAPIService`, `NetreoIncident`, `NetreoDevice`, `NetreoAPIConfiguration`)
> and AppStorage keys (`netreo_base_url`, `netreo_api_key`, etc.) still use
> the legacy prefix for backwards compatibility. This applies across `ios/`
> and any future code that talks to BHNM.

## Structure

| Path | Purpose |
|---|---|
| `ios/` | Native Swift/SwiftUI iOS app. Primary platform. Distributed via App Store / TestFlight. |
| `middleware/` | Python/FastAPI service. Handles BHNM webhook ingestion and APNs / Web Push delivery. |
| `pwa/` | Progressive Web App (React/TypeScript), targeting Android via Web Push. |
| `shared/` | Specifications and documentation. Not deployed. Source of truth for feature parity and API contracts. |
| `docs/superpowers/` | Claude Code brainstorming output. `specs/YYYY-MM-DD-<topic>-design.md` holds approved designs; `plans/YYYY-MM-DD-<topic>.md` holds the derived step-by-step implementation plan. Each feature flows spec → plan → code. |

## Platform Strategy

The full decision record is in `shared/DECISION.md` (April 2026). Summary:

- **iOS native (Swift)** is the lead platform and the authoritative push delivery channel (APNs).
- **PWA (React/TypeScript)** targets Android users via Web Push, and serves as a web dashboard for desktop/browser access. **iOS users of the PWA are directed to install the native app** — iOS Web Push is unreliable and EU-politically-unstable.
- A **single Python/FastAPI middleware** delivers push to both iOS (APNs `.p8`) and Android PWA (VAPID Web Push).

## Feature Parity Rule

Features are implemented on `ios/` first. As `pwa/` matures, features land
on both platforms unless explicitly marked platform-specific in
`shared/feature-spec.md`.

**Always update `shared/feature-spec.md` before or alongside implementation.**

## Doctrine: never render unverified state as healthy

**If the app has not verified a thing is good, it must not draw it the way it draws good.**
Three states, always: *verified good*, *verified bad*, and **unverified** — and the third gets
its own appearance, never the healthy one.

This is written as a rule because it has now been shipped three times, in three different
places, by three different mechanisms:

1. **The device icon showed green for a host BHNM reported `DOWN`.** Fixed in its own wave
   (`docs/evidence/2026-09-03-...`), because "no bad news yet" was being drawn as good news.
2. **"Registered and active" is local belief.** Both clients render it from their own stored
   flag, never confirmed against the middleware. A phone that is not registered at all shows
   the same label as one that is.
3. **The push toggle reads ON while the device receives nothing.** Two independent causes found
   on 2026-09-15 — a QR import that never selected the connection, and iOS notification
   permission denied at the OS level, which the app never reads. In both cases the UI asserted
   health it had never checked.

Each of those cost real engineer-hours and, in a paging product, each meant somebody believed
they were covered when they were not. A green affordance is a **claim**. Do not make it on
cached data, on a local flag, on a request that has not returned, or on the absence of an
error — only on a fact the app has confirmed and can date.

Practical form: prefer "Registered · confirmed 2 minutes ago" to "Registered"; show
"Can't reach the server · last confirmed 14:03" rather than leaving the last good state on
screen; and when a check is in flight, say so instead of showing the previous answer as
current. Design detail for the push case is in
`docs/superpowers/specs/2026-09-15-webhook-secret-header-auth-design.md` Part 11.

## Push Notification Architecture

```
BHNM Incident → Webhook → bhnm-apns middleware → APNs (iOS) / Web Push (Android) → device
```

- Middleware (producer): see `middleware/CLAUDE.md`
- iOS consumer: see `ios/CLAUDE.md`
- PWA consumer: see `pwa/CLAUDE.md` (stub)
- Cross-platform payload contract: `shared/push-payload-spec.md`

Do NOT attempt to implement Critical Alerts or Time Sensitive notifications in the PWA — the Web Push API does not support them on iOS. (BeNeM does not use these on the native app either; see `shared/DECISION.md`.)

## Sessions

- **Cross-platform feature work** (spans ios + middleware + pwa): open Claude Code from the repo root.
- **iOS-specific deep dives:** open from `ios/`.
- **Middleware-specific work:** open from `middleware/`.
- **PWA-specific work:** open from `pwa/`.

Always commit before switching session context.

## Minimum BHNM version

**26.1.02.** The iOS app uses UID-based device identity, pagination,
model/serial fields, and interface details — all require 26.1.01+.

## API

All BHNM API endpoints used by BeNeM are documented in
`shared/BHNM_API_REFERENCE.md`.
