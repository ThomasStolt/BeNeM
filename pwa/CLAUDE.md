# BeNeM PWA

React/TypeScript Progressive Web App. Targets Android users via Web Push.
iOS users are directed to the native app for reliable push notifications.

> Part of the BeNeM monorepo. See `../CLAUDE.md` for cross-cutting rules,
> `../shared/feature-spec.md` for the canonical feature list, and
> `../shared/push-payload-spec.md` for the notification payload contract.

> **Status:** Not yet scaffolded. This file is a placeholder. When PWA work
> begins, expand this with framework/library choices, build tooling, and
> deployment target.

## Key facts (target state)

- **Web Push:** VAPID-based, delivered via `../middleware/`
- **iOS caveat:** Push on iOS is unreliable (subscription expiry bug, no Time Sensitive entitlement) and EU-regulatorily unstable. Do NOT position Web Push as the primary alert channel for iOS users. Display a prominent banner to iOS users recommending the native app for incident alerts. See `../shared/DECISION.md` for the full rationale.

## Feature spec

Refer to `../shared/feature-spec.md`. PWA-specific behaviour is marked there.
