# BeNeM Platform Strategy Decision

**Date:** April 2026
**Status:** Adopted

---

## Background

BeNeM is a network monitoring and incident alerting application built on top of
BMC Helix Network Management (BHNM). Its primary function is delivering timely,
reliable push notifications to engineers when incidents occur — including when
their phone is locked, screen-down on a desk during a lunch break.

The core question evaluated here was: **can a Progressive Web App (PWA) replace
or supplement the native iOS app, and how should the codebase be structured to
support multiple platform targets without excessive duplication?**

---

## Push Notification Capability Assessment

Push notification reliability is the non-negotiable requirement for BeNeM.
An incident alerting tool that silently fails to deliver notifications provides
negative value — it creates a false sense of coverage.

The following matrix was used to evaluate iOS native (APNs) against PWA Web Push
on both iOS and Android:

| Feature                                | BeNeM iOS (APNs)                          | PWA iOS                             | PWA Android      |
|----------------------------------------|-------------------------------------------|-------------------------------------|------------------|
| Lock screen alert                      | ✅ Reliable                               | ⚠️ When it works                    | ✅ Reliable      |
| Focus Mode bypass (Time Sensitive)     | ✅ Supported                              | ❌ Not available                    | ❌ Not available |
| Silent switch bypass (Critical Alerts) | ✅ Available (requires Apple entitlement) | ❌ Not available                    | ❌ Not available |
| Push subscription stability            | ✅ Stable                                 | 🔴 Known expiry bug on iOS WebKit   | ✅ Stable        |
| Background sync                        | ✅ Yes                                    | ❌ Not supported on iOS             | ✅ Yes           |
| EU regulatory stability                | ✅ Unaffected                             | 🔴 Politically unstable (DMA/Apple) | ✅ Unaffected    |
| Onboarding friction                    | Low (App Store)                           | High (manual Add to Home Screen)    | Medium           |

### Key findings

**iOS PWA push is not suitable for incident alerting.** Three compounding issues
make it unreliable for this use case:

1. Push subscriptions on iOS WebKit silently expire after one to two weeks,
   causing notifications to stop arriving without any indication to the user.
   This is a known, unfixed bug reported widely in the developer community.

2. PWA Web Push cannot access the Time Sensitive notification entitlement,
   meaning notifications are silenced by Focus Mode and Do Not Disturb — exactly
   the scenario BeNeM must penetrate (phone on desk, engineer at lunch).

3. EU users (the primary deployment context) are subject to Apple's ongoing
   DMA compliance decisions. Apple temporarily removed PWA standalone support
   in the EU in early 2024, reversed after backlash, but the underlying
   regulatory instability remains. As of early 2026 no third-party browser
   engines have adopted BrowserEngineKit, leaving Apple in sole control of
   iOS PWA capabilities.

**Android PWA push is viable.** Web Push on Android is mature, subscription
stability is solid, and the platform treats PWAs as first-class citizens.
It is an appropriate delivery channel for Android users.

---

## Decision

### Lead platform: iOS native (Swift)

The iOS app remains the primary and most capable BeNeM client. APNs is the
authoritative push delivery channel. The iOS app is the reference implementation
for all features.

### Secondary platform: PWA (React/TypeScript), targeting Android

A PWA is developed as a secondary client, explicitly targeting Android users
via Web Push. The PWA is also useful as a web dashboard for desktop/browser
access where push notification reliability is not required.

**iOS users who encounter the PWA are directed to install the native app**
for reliable incident alerts. The PWA displays a persistent banner communicating
this recommendation. Push notifications are not presented as a PWA feature
for iOS users.

### Push infrastructure: shared middleware

A single Python/FastAPI middleware service (`middleware/`) handles all
push delivery:
- APNs (`.p8` Auth Key) for iOS native app users
- Web Push (VAPID keys) for Android PWA users

This means new notification types are defined once and delivered to both
platforms from a single code path.

---

## Repository Structure

A monorepo structure is adopted to support cross-cutting changes — particularly
new notification types that span middleware, iOS, and PWA simultaneously:

```
benem/
├── ios/          — Native Swift/SwiftUI app
├── middleware/   — FastAPI push notification service
├── pwa/          — React/TypeScript PWA
└── shared/       — Specifications and API contracts (not deployed)
```

### Why monorepo over separate repositories

- New notification payload types require coordinated changes across middleware
  (producer), iOS (consumer), and PWA (consumer). A monorepo allows this to
  be a single commit with a single review, rather than three coordinated PRs
  across three repositories.
- A shared `feature-spec.md` and `push-payload-spec.md` in `shared/` serve
  as the coordination layer between platforms, preventing behavioural drift.
- Claude Code sessions opened at the monorepo root have full context across
  all three subprojects, enabling cross-cutting feature implementation in a
  single session.

### Duplication assessment

The duplication concern in a two-platform approach is real but bounded.
Business logic lives entirely in the BHNM API and the middleware — both clients
are thin display layers. The duplicated surface is UI components and API
networking glue. This is estimated at 60–70% of the effort of two fully
independent codebases maintained by separate teams, because the *what* is
always specified once in `shared/` before implementation begins.

---

## What was explicitly ruled out

**Cross-platform frameworks (React Native, Flutter):** These would unify the
iOS and Android clients at the cost of giving up native Swift. BeNeM's iOS
push notification requirements — Time Sensitive entitlements, CryptoKit-based
deep link encryption, APNs `.p8` auth — are deeply tied to the native iOS
stack. Rewriting in a cross-platform framework to gain Android support would
sacrifice the reliability properties that make BeNeM valuable on iOS.

**PWA-only strategy:** Ruled out by the push notification assessment above.
A PWA-only BeNeM on iOS would be an incident alerting tool that silently
fails to alert during Focus Mode and whose subscriptions expire unpredictably.
This is not an acceptable trade-off.

---

## Review trigger

This decision should be reviewed if:
- Apple resolves the iOS PWA push subscription stability bug in a public iOS release
- EU regulatory changes result in materially improved PWA capabilities on iOS
- The Time Sensitive entitlement or equivalent becomes available to Web Push on iOS
