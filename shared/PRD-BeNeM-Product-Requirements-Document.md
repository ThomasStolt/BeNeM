# BeNeM — Product Requirements Document (PRD)

**Document Version:** 2.0
**Last Updated:** 2026-04-07
**Status:** Living document for development guidance
**Product Name:** BeNeM — BMC Helix Network Management Mobile Client

> **Naming note:** BMC Helix Network Management (BHNM) was formerly known as **Netreo**. Internal code identifiers (e.g. `NetreoAPIService`, `NetreoIncident`) still use the legacy prefix for backwards compatibility.

---

## 1. Document control

| Version | Date       | Author/Change |
|--------|------------|----------------|
| 1.0    | 2025-03-17 | Initial PRD from codebase analysis |
| 1.1    | 2026-03-19 | Updated to reflect BHNM rebrand (formerly Netreo); updated current state |
| 2.0    | 2026-04-07 | Major rewrite: monorepo structure, PWA platform, push notifications, current feature state |

**Purpose of this document**
This PRD describes the BeNeM product as understood from the current codebase, and is intended to guide prioritization, feature development, and technical decisions.

**How to use this PRD**
- **Product / project owners:** Use for scope, prioritization, and alignment with stakeholders.
- **Developers:** Use for implementation scope, acceptance criteria, and technical constraints.
- **QA:** Use for test scenarios and regression focus.
- **New contributors:** Use as the single source of truth for "what BeNeM is and where it's going."

---

## 2. Executive summary

**BeNeM** is a multi-platform network management client that connects to **BMC Helix Network Management** (BHNM, on-premises) to give users a mobile-friendly way to:

- **Receive** real-time push notifications when incidents occur (APNs for iOS, Web Push for Android)
- **Monitor** network devices and incidents from a dashboard with tactical overview
- **Manage** incidents (acknowledge, unacknowledge) directly from mobile devices
- **View** device details including performance charts (CPU, Memory, Bandwidth, Latency)
- **Configure** connections via QR code scanning or manual entry, with multi-server support

The project consists of three components in a monorepo:
- **iOS app** (Swift/SwiftUI) — lead platform, App Store / TestFlight
- **PWA** (React/TypeScript) — targets Android users via Web Push, also serves as a web dashboard
- **Middleware** (Python/FastAPI) — bridges BHNM webhooks to APNs and Web Push, proxies API requests

See `shared/DECISION.md` for the full platform strategy rationale.

---

## 3. Product overview

### 3.1 Vision

BeNeM is the go-to **lightweight mobile client** for BHNM users who want to check network health, triage incidents, and acknowledge alerts from a phone or tablet without using the full BHNM web UI. Its primary differentiator is **reliable push notification delivery** — including when the phone is locked and in Focus Mode (iOS).

### 3.2 Goals

- **Reliability:** Timely push notifications that penetrate Do Not Disturb and Focus Mode (iOS via Time Sensitive entitlement).
- **Usability:** Fast, clear access to incidents and devices with minimal configuration (QR code scan or manual API key entry).
- **Cross-platform:** iOS native for reliability, PWA for Android and desktop browser access.
- **Extensibility:** Architecture that allows adding more BHNM capabilities without rewriting existing code.

### 3.3 Target users

- **Network operators / NOC staff** who need a quick view of incidents and device status on the go.
- **IT admins** who manage devices in BHNM and want to respond to alerts from a phone or tablet.
- **Organizations** already using BHNM who want push-based incident alerting beyond the web UI.

### 3.4 Out of scope

- Replacing the BHNM web UI for full configuration.
- Supporting other network management systems (BHNM only).
- iOS PWA push notifications (unreliable — iOS users are directed to the native app).

---

## 4. Current state (April 2026)

### 4.1 Platform status

| Platform | Status | Distribution |
|---|---|---|
| iOS (Swift/SwiftUI) | Production | App Store / TestFlight |
| PWA (React/TypeScript) | Production | `https://benem.hurrikap.org` |
| Middleware (Python/FastAPI) | Production | `https://bhnm-apns.hurrikap.org` (Docker + Caddy) |

### 4.2 iOS app architecture

- **Entry point:** `BeNeMApp.swift` → `ContentView()` with tab-based navigation (Dashboard, Incidents, Devices, Settings)
- **Service layer:** `NetreoAPIService` — single service for all BHNM API calls, uses legacy form-encoded API
- **Models:** `NetreoDevice`, `NetreoIncident`, `IncidentDetail`, `GroupSummary`, `PerformanceInstance`
- **ViewModels:** `IncidentListViewModel`, `DeviceListViewModel`, `DeviceDetailViewModel`, `TacticalViewModel`
- **Push:** APNs via `AppDelegate`, notification tap deep-links to incident detail
- **QR onboarding:** `DeepLinkHandler` decrypts AES-256-GCM `benem://configure` payloads

### 4.3 PWA architecture

- **Framework:** React 19 + TypeScript + Vite
- **State:** React Query for server state, localStorage for configuration
- **API client:** Form-encoded POST via fetch, proxied through middleware
- **Push:** VAPID Web Push via service worker (`sw.ts`)
- **QR onboarding:** Web Crypto API for AES-256-GCM decryption, html5-qrcode for camera

### 4.4 Middleware architecture

- **Framework:** Python / FastAPI / uvicorn
- **Push delivery:** APNs (HTTP/2 via httpx, JWT `.p8` auth) + Web Push (VAPID via pywebpush)
- **Database:** SQLite for device tokens and Web Push subscriptions
- **Proxy:** Catch-all reverse proxy to BHNM servers, with per-request target resolution via `X-BHNM-Target` header or `servers.json` lookup
- **TLS:** Caddy reverse proxy handles Let's Encrypt certificates

### 4.5 Connection and configuration

| Setting | iOS Storage | PWA Storage |
|---|---|---|
| BHNM server URL | `SavedConnection.bhnmURL` (UserDefaults JSON) | `server.bhnmUrl` (localStorage JSON) |
| Middleware URL | `SavedConnection.middlewareURL` | `server.middlewareUrl` |
| API Key | `SavedConnection.apiKey` | `server.apiKey` |
| PIN (optional) | `SavedConnection.pin` | `server.pin` |
| Webhook secret | `SavedConnection.webhookSecret` | `server.pushWebhookSecret` |
| ACK username | `SavedConnection.ackUser` | `server.ackUser` |

Both platforms support multiple saved servers with per-server push notification configuration.

---

## 5. Implemented features

See `shared/feature-spec.md` for the canonical per-feature specification with platform-specific details.

| Feature | iOS | PWA | API |
|---|---|---|---|
| Incident list | Shipped | Shipped | `POST /api/incident_api.php` |
| Incident detail | Shipped | Shipped | `POST /api/incident_api.php` (getincidentdetail) |
| ACK / UnACK | Shipped | Shipped | `POST /fw/index.php?r=restful/incident/acknowledge` |
| Dashboard (H/S/T/A) | Shipped | Shipped | `POST /fw/index.php?r=restful/tactical-overview/data` |
| Device list (paginated) | Shipped | Shipped | `POST /fw/index.php?r=restful/devices/list` |
| Device search | Shipped | Shipped | `POST /fw/index.php?r=restful/devices/find` |
| Device detail | Shipped | Shipped | `POST /fw/index.php?r=restful/devices/find` |
| Performance charts | Shipped | Shipped | `POST /fw/index.php?r=restful/devices/timeseries-metrics` |
| Tactical drill-down | Shipped | Shipped | `POST /fw/index.php?r=restful/tactical-overview/data` |
| Push notifications | Shipped (APNs) | Shipped (Web Push) | Middleware `/webhook` |
| Multi-server management | Shipped | Shipped | N/A (client-side) |
| QR server onboarding | Shipped | Shipped | AES-256-GCM encrypted `benem://configure` URLs |
| Auto-refresh (120s) | Shipped | Shipped | N/A (client-side timer) |

---

## 6. Functional requirements

### 6.1 Implemented requirements

| ID | Requirement | Priority | Status |
|----|-------------|----------|--------|
| F1 | User can configure BHNM connection (URL, API key, PIN) and persist. | P0 | Done |
| F2 | Dashboard shows active incident count, device count, and H/S/T/A alarm overview. | P0 | Done |
| F3 | Incident list with severity badges, alarm counts, swipe ACK/UnACK, and auto-refresh. | P0 | Done |
| F4 | Tactical overview with per-group alarm badges and filter-to-alarms toggle. | P0 | Done |
| F5 | Push notifications for new incidents with deep-link to incident detail. | P0 | Done |
| F6 | Paginated device list with server-side search. | P0 | Done |
| F7 | Device detail with info card, related incidents, and performance charts. | P1 | Done |
| F8 | Multi-server management with per-server push configuration. | P1 | Done |
| F9 | QR code scanning for automated server onboarding. | P1 | Done |

### 6.2 Planned requirements

| ID | Requirement | Priority | Notes |
|----|-------------|----------|-------|
| F10 | Proxy auth hardening — separate `proxy_token` from `webhookSecret`. | P1 | Plan at `docs/superpowers/plans/2026-04-07-proxy-auth-hardening.md` |
| F11 | API response caching in middleware for large environments (4K-13K devices). | P2 | Deferred — see project memory |
| F12 | Per-device alarm status badges (H/S/T/A) in device list. | P2 | No per-device endpoint identified yet |

---

## 7. Non-functional requirements

| ID | Category | Requirement |
|----|----------|-------------|
| NFR1 | Performance | Dashboard and lists load within a few seconds; auto-refresh every 120 s. |
| NFR2 | Security | API keys and secrets not logged in production builds; AES-256-GCM for QR payloads. |
| NFR3 | Compatibility | Minimum BHNM version: 26.1.02 (UID-based identity, pagination, model/serial fields). |
| NFR4 | Maintainability | Single service layer per platform; shared feature spec drives parity. |
| NFR5 | Push reliability | iOS: APNs with Time Sensitive entitlement. Android: VAPID Web Push. iOS PWA users directed to native app. |

---

## 8. Technical debt and known gaps

### 8.1 Active issues

1. **Proxy auth disabled** — `X-Proxy-Token` validation removed from middleware after a broken deployment. Hardening plan exists but not yet implemented.

2. **`proxy_token` not parsed from QR** — iOS `DeepLinkHandler` ignores the `proxy_token` field in QR payloads; reuses `webhookSecret` instead. Part of the hardening plan.

3. **PWA doesn't send `X-Proxy-Token`** — `postForm()` never includes the proxy auth header. Part of the hardening plan.

4. **Push payload lacks `severity`** — The middleware doesn't pass incident severity in the push payload. The `severity` field in the Web Push payload is always empty string.

### 8.2 Resolved (since PRD v1.1)

- ~~Device list returns mock data~~ — Real device parsing implemented (paginated, UID-based)
- ~~Debug logging in production~~ — Print statements wrapped in `#if DEBUG` (April 2026)
- ~~"Simple" flow duplication~~ — `SimpleContentView`, `SimpleNetreoService`, and all Simple* views removed
- ~~H/S/T alarm row distinction~~ — Now uses `restful/tactical-overview/data` endpoint directly (pre-aggregated)
- ~~`fetchDevicePerformance` stub~~ — Full performance chart implementation with category discovery and timeseries batch fetch
- ~~Multiple saved servers~~ — Implemented on both platforms
- ~~Auto Discovery (SNMP scan)~~ — Removed; QR code onboarding replaces it

---

## 9. Roadmap

### Current focus: Proxy auth hardening (P1)

Implement proper `X-Proxy-Token` authentication across all three components. See `docs/superpowers/plans/2026-04-07-proxy-auth-hardening.md`.

### Next: Performance and scale (P2)

- API response caching in middleware for large BHNM environments
- Investigate per-device alarm status endpoint

### Backlog

- Accessibility pass (labels, Dynamic Type, VoiceOver)
- Push notification severity in payload
- Topology view (device connectivity via interface IPs)

---

## 10. Appendices

### Appendix A — Glossary

| Term | Definition |
|------|------------|
| BHNM | BMC Helix Network Management — network monitoring platform (on-prem). Formerly known as **Netreo**. |
| BeNeM | This project: "Be Netreo Mobile" (name predates the rebrand; now the BHNM mobile client). |
| Legacy API | BHNM PHP-style APIs (form-encoded POST to `/fw/index.php?r=restful/...` or `/api/*_api.php`). |
| APNs | Apple Push Notification Service — delivers push notifications to iOS devices. |
| VAPID | Voluntary Application Server Identification — Web Push authentication standard. |
| Middleware | The `bhnm-apns` FastAPI service that bridges BHNM webhooks to push notifications and proxies API requests. |

### Appendix B — Key files

| Area | iOS | PWA | Middleware |
|------|-----|-----|-----------|
| Entry point | `BeNeMApp.swift` | `main.tsx` | `main.py` |
| API service | `NetreoAPIService.swift` | `src/lib/api/client.ts` | N/A (proxy) |
| Configuration | `NetreoAPIConfiguration.swift` | `src/lib/config.ts` | `config.py` |
| Push handling | `AppDelegate.swift` | `src/sw.ts` | `apns.py`, `webpush.py` |
| Deep links / QR | `DeepLinkHandler.swift` | `src/lib/qr/decrypt.ts` | `benem-admin/main.py` |
| Models | `NetreoIncident.swift`, `NetreoDevice.swift` | `src/lib/api/types.ts` | N/A |

### Appendix C — References

- Platform strategy decision: `shared/DECISION.md`
- Feature specification: `shared/feature-spec.md`
- Push payload contract: `shared/push-payload-spec.md`
- BHNM API reference: `shared/BHNM_API_REFERENCE.md`
- Credentials overview: `shared/credentials-and-keys-overview.md`

---

*End of PRD. Use this document to align stakeholders and guide the next development cycles.*
