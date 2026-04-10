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

- **iOS native (Swift)** is the lead platform and the authoritative push delivery channel (APNs with Time Sensitive entitlement support).
- **PWA (React/TypeScript)** targets Android users via Web Push, and serves as a web dashboard for desktop/browser access. **iOS users of the PWA are directed to install the native app** — iOS Web Push is unreliable and EU-politically-unstable.
- A **single Python/FastAPI middleware** delivers push to both iOS (APNs `.p8`) and Android PWA (VAPID Web Push).

## Feature Parity Rule

Features are implemented on `ios/` first. As `pwa/` matures, features land
on both platforms unless explicitly marked platform-specific in
`shared/feature-spec.md`.

**Always update `shared/feature-spec.md` before or alongside implementation.**

## Push Notification Architecture

```
BHNM Incident → Webhook → bhnm-apns middleware → APNs (iOS) / Web Push (Android) → device
```

- Middleware (producer): see `middleware/CLAUDE.md`
- iOS consumer: see `ios/CLAUDE.md`
- PWA consumer: see `pwa/CLAUDE.md` (stub)
- Cross-platform payload contract: `shared/push-payload-spec.md`

Do NOT attempt to implement iOS-style Critical Alerts or Time Sensitive notifications in the PWA — the Web Push API does not support them on iOS.

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
