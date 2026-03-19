# BeNeM — Product Requirements Document (PRD)

**Document Version:** 1.1
**Last Updated:** 2026-03-19
**Status:** Living document for development guidance
**Product Name:** BeNeM — BMC Helix Network Management Mobile Client

> **Naming note:** BMC Helix Network Management (BHNM) was formerly known as **Netreo**. Internal code identifiers (e.g. `NetreoAPIService`, `NetreoIncident`) still use the legacy prefix for backwards compatibility.

---

## 1. Document control

| Version | Date       | Author/Change |
|--------|------------|----------------|
| 1.0    | 2025-03-17 | Initial PRD from codebase analysis |
| 1.1    | 2026-03-19 | Updated to reflect BHNM rebrand (formerly Netreo); updated current state |

**Purpose of this document**
This PRD describes the BeNeM product as understood from the current codebase, and is intended to guide prioritization, feature development, and technical decisions. It follows common product-management practice: problem statement, goals, current state, requirements, and roadmap.

**How to use this PRD**
- **Product / project owners:** Use for scope, prioritization, and alignment with stakeholders.
- **Developers:** Use for implementation scope, acceptance criteria, and technical constraints.
- **QA:** Use for test scenarios and regression focus.
- **New contributors:** Use as the single source of truth for "what BeNeM is and where it's going."

---

## 2. Executive summary

**BeNeM** is a native **network management client** that connects to **BMC Helix Network Management** (BHNM, on-premises or SaaS) to give users a mobile-friendly way to:

- **Monitor** network devices and incidents
- **View** a dashboard of active incidents and device status across Categories, Sites, and Business Workflows
- **Manage** incidents (acknowledge, unacknowledge) directly from the device
- **Configure** connection (base URL, API key, PIN, API version, timeouts)

The app is built with **Swift/SwiftUI**, uses a **tab-based** layout (Dashboard, Incidents, Devices, Settings), and supports multiple **BHNM API styles** (legacy PHP, v1, v2, OpenAPI). There is a second, **"Simple"** code path that uses different BHNM REST endpoints and includes device interfaces, interface performance, and latency—but this path is **not** the one launched from the main app entry point today.

**Key takeaway for development:**
The main flow is functional for real incident and device data. Next priorities are completing the Tactical Overview alarm accuracy, exposing device details, and deciding how to integrate or retire the "Simple" path.

---

## 3. Product overview

### 3.1 Vision

BeNeM is the go-to **lightweight mobile client** for BHNM users who want to check network health, triage incidents, and acknowledge alerts from a phone or tablet without using the full BHNM web UI.

### 3.2 Goals

- **Usability:** Fast, clear access to incidents and devices with minimal configuration (base URL + API key).
- **Reliability:** Clear connection status and error messages; behavior that degrades gracefully when the BHNM server or API is unavailable.
- **Flexibility:** Support for different BHNM deployments (legacy PHP APIs, v1/v2/OpenAPI) and optional PIN for SaaS.
- **Extensibility:** Architecture that allows adding more BHNM capabilities (e.g. device performance, interfaces) without rewriting the app.

### 3.3 Target users

- **Network operators / NOC staff** who need a quick view of incidents and device status on the go.
- **IT admins** who manage devices in BHNM and want to respond to alerts from a phone or tablet.
- **Organizations** already using BHNM who want a dedicated native client instead of the web UI only.

### 3.4 Out of scope (for this PRD)

- Replacing the BHNM web UI for full configuration.
- Supporting other network management systems (BHNM only).
- Backend or server-side components (BeNeM is a client only).

---

## 4. Current state analysis

### 4.1 Entry point and navigation

- **App entry:** `BeNeMApp.swift` → `ContentView()`.
- **Tabs:**
  - **Home:** If base URL and API key are set and `NetreoAPIService` is created: **Dashboard**, **Incidents**, **Devices**.
  - If not configured: **Welcome** (with Quick Setup) and **Settings**.
  - **Settings** is always shown as a tab.

`SimpleContentView` and `SimpleNetreoService` are **not** used by the main entry point; they form an alternative flow (e.g. for a different build or future merge).

### 4.2 Connection and configuration

| Setting           | Storage        | Used by |
|-------------------|----------------|--------|
| Base URL          | `netreo_base_url` (AppStorage) | ContentView, QuickConfigView, SettingsView |
| API Key           | `netreo_api_key` (AppStorage) | Same |
| PIN (SaaS)        | `netreo_pin` (AppStorage)     | Same |
| API Version       | `netreo_api_version` (legacy/v1/v2/openapi) | `NetreoAPIConfiguration` |
| Timeout           | `netreo_timeout` (e.g. 10–120 s) | `NetreoAPIService` |
| Retry Count       | `netreo_retry_count` (e.g. 1–10) | `NetreoAPIService` |

> AppStorage keys retain the `netreo_` prefix to preserve existing user settings across updates.

### 4.3 Main flow features (ContentView → NetreoAPIService)

| Feature | Implementation | Notes |
|--------|----------------|-------|
| **Dashboard** | `DashboardView` | Status cards (active incidents, total devices); Tactical Overview (Category / Site / Business Workflow). Auto-refreshes every 120 s. |
| **Incidents** | `IncidentListView` + `IncidentListViewModel` | Live list with severity badges and alarm counts; swipe to ACK/UnACK; filters; auto-refresh. |
| **Tactical Overview** | `GroupListView` + `TacticalViewModel` | Per-group device count + 5-color alarm badges; filter to show only groups with active alarms. Alarm status derived from incident detail API. |
| **Incident Detail** | `IncidentDetailView` | Primary alarms, related alarms, incident state log. |
| **Settings** | `SettingsView` | All connection/API options; Test Connection with detailed diagnostics alert; Auto Discovery; Debug panels. |

### 4.4 "Simple" flow (SimpleNetreoService — not main entry)

- Uses BHNM REST-style endpoints (e.g. `/fw/index.php?r=restful/...`).
- **SimpleContentView:** Connect with server IP + API key → device list.
- **SimpleNetreoService** implements device list, device services, interfaces, interface performance, device latency.
- **InterfacePerformanceView** and **DeviceLatencyView** are built for `SimpleNetreoService`.
- **DeviceInterfacesView** is currently a placeholder (no real data binding).

### 4.5 Architecture (main flow)

- **UI:** SwiftUI views; tab-based.
- **State:** `@AppStorage` for config; `@StateObject` / `@ObservedObject` for ViewModels.
- **ViewModels:** `IncidentListViewModel`, `DeviceListViewModel`, `TacticalViewModel`.
- **Service layer:** `NetreoAPIService` (single place for all BHNM API calls; uses `NetreoAPIConfiguration` and `NetreoEndpoint`).
- **Models:** `NetreoDevice`, `NetreoIncident`, `IncidentDetail`, `GroupSummary`, etc.

### 4.6 API abstraction

- **`NetreoAPIConfiguration`:** Base URL normalization, API version → path prefix.
- **`NetreoEndpoint`:** Enum for device list/add/delete/rename, incidents, acknowledgment, categories, sites; each endpoint knows path and HTTP method per version.
- **`NetreoAPIService`:** Implements legacy (form-encoded) vs modern (JSON, Bearer) paths.

### 4.7 Data models (summary)

- **`NetreoDevice`:** ip, name, hostname, status, deviceType, lastUpdated, siteID, categoryID, snmpCommunity, isActive.
- **`NetreoIncident`:** incidentID, deviceIP/deviceName, summary, description, severity (critical→informational), status (active/acknowledged/resolved/closed), startTime.
- **`GroupSummary`:** id, name, hostsGreen/Blue/Yellow/Orange/Red — aggregated from incident alarm counts.

---

## 5. Functional requirements

### 5.1 Current (as-implemented) requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| F1 | User can set BHNM base URL, API key, and optional PIN and persist them. | P0 |
| F2 | User can select API version (legacy, v1, v2, openapi) and adjust timeout/retry. | P1 |
| F3 | When configured, user sees Dashboard, Incidents, and Devices tabs. | P0 |
| F4 | Dashboard shows counts of active incidents and total devices; links to Tactical Overview. | P0 |
| F5 | Incidents list shows severity and status; user can filter, ACK/UnACK (swipe), and see alarm detail. | P0 |
| F6 | Tactical Overview shows per-group device count and 5-color alarm status; filter to alarms-only. | P0 |
| F7 | Settings screen exposes all connection and API options with Test Connection diagnostics. | P0 |
| F8 | Auto Discovery scans local Wi-Fi /24 for BHNM servers. | P1 |

### 5.2 Intended (to be implemented) requirements

| ID | Requirement | Priority | Notes |
|----|-------------|----------|-------|
| F9 | Device list shows real devices from BHNM API (no mock data in production path). | P0 | Current implementation returns mock devices in legacy and modern paths. |
| F10 | H/S/T alarm rows in Tactical Overview correctly separate host, service, and threshold alarms. | P1 | Currently all alarms go to H row; API does not clearly distinguish types. |
| F11 | User can rename a device from the device list or detail (API/ViewModel already support it). | P2 | Add UI (e.g. context menu or edit screen). |
| F12 | Optional: Device detail view with performance metrics when API provides them. | P2 | Requires implementing `fetchDevicePerformance`. |
| F13 | Optional: Device interfaces and interface performance (align Simple flow with main flow). | P2 | Requires design decision: extend `NetreoAPIService` or migrate `SimpleNetreoService`. |

### 5.3 Edge cases and error behavior

- **Empty/missing config:** Show Welcome + Quick Config; no Dashboard/Incidents until base URL and API key are set.
- **Connection failure:** All list/dashboard loads should surface a user-visible error.
- **API version mismatch:** Show clear error if server responds with unexpected format.
- **Partial data:** Incidents and devices should tolerate missing optional fields without crashing.

---

## 6. Non-functional requirements

| ID | Category | Requirement |
|----|----------|-------------|
| NFR1 | Performance | Dashboard and lists should load within a few seconds; auto-refresh every 120 s. |
| NFR2 | Security | API key and PIN must not be logged or exposed; use SecureField for secrets. |
| NFR3 | Compatibility | Support BHNM API versions currently abstracted (legacy, v1, v2, openapi). |
| NFR4 | Maintainability | Prefer a single service layer (`NetreoAPIService`) and shared models for all BHNM data. |
| NFR5 | Accessibility | Use semantic labels; support Dynamic Type and VoiceOver where applicable. |
| NFR6 | Offline / poor connectivity | Show last known data and a clear "connection failed" state; avoid silent failures. |

---

## 7. Gaps and technical debt

### 7.1 Critical (should fix soon)

1. **Device list returns mock data**
   In `NetreoAPIService`, both `performLegacyDeviceRequest` and `performModernDeviceRequest` return `createMockDevices()`. Real device parsing must be implemented; mock used only for tests.

2. **Debug logging in production path**
   Remove or guard `print(...)` in views and API parsing so they do not run in release builds.

### 7.2 Important (improve when touching related code)

3. **Duplicate "Simple" vs main flow**
   Two parallel implementations exist. Decide: merge into one service and navigation, or clearly separate as a build flavor and document it.

4. **H/S/T alarm row distinction**
   All alarms currently go to the H row. The BHNM API does not clearly label incident type (host/service/threshold); a heuristic or additional API call may be needed.

5. **`fetchDevicePerformance` is a stub**
   Returns `[]`; either implement against BHNM API or remove from public API until ready.

### 7.3 Nice to have

6. **Rename device UI** — ViewModel and API support rename; add a row action or edit screen.
7. **Unified error handling** — Centralize API errors and user-facing messages.
8. **Multiple saved servers** — List of BHNM server configurations the user can switch between.

---

## 8. Roadmap and prioritization

### Phase 1 — Stabilize core (P0)

- Implement real device list parsing (replace mock in production path).
- Remove or gate debug prints in release builds.

### Phase 2 — Quality and UX (P1)

- Improve H/S/T alarm row accuracy.
- Improve error messages and offline/error state across all screens.
- Optional: Add unit tests for ViewModels and API parsing.

### Phase 3 — Feature parity and cleanup (P2)

- Add device rename UI.
- Decide strategy for "Simple" flow: integrate or deprecate.
- Implement or explicitly defer `fetchDevicePerformance` and device/interface detail screens.

### Phase 4 — Enhancements (backlog)

- Device detail with performance charts.
- Interface list and interface performance in main flow.
- Accessibility pass (labels, Dynamic Type, VoiceOver).
- Support multiple saved BHNM servers.

---

## 9. Success criteria

- **Phase 1:** Real devices shown in device list; no mock data in production; no unnecessary console noise in release.
- **Phase 2:** Errors are visible and understandable on all screens; H/S/T alarm rows closer to actual BHNM behavior.
- **Phase 3:** Device rename is available; strategy for Simple vs main flow is decided and documented.

---

## 10. Appendices

### Appendix A — Glossary

| Term | Definition |
|------|------------|
| BHNM | BMC Helix Network Management — network monitoring and management platform (on-prem or SaaS). Formerly known as **Netreo**. |
| BeNeM | This client app: "Be Netreo Mobile" (name predates the rebrand; now the BHNM mobile client). |
| Legacy API | BHNM PHP-style APIs (e.g. form-encoded POST to `/api/incident_api.php`). |
| Modern API | BHNM v1/v2/OpenAPI REST-style APIs (JSON, Bearer auth). |
| Main flow | `ContentView` → `NetreoAPIService` → Dashboard, Incidents, Devices. |
| Simple flow | `SimpleContentView` → `SimpleNetreoService` → device list, interfaces, performance, latency (not used by default entry point). |

### Appendix B — File and component reference

| Area | Key files |
|------|------------|
| App entry | `BeNeMApp.swift`, `ContentView.swift` |
| Config / API | `NetreoAPIConfiguration.swift`, `NetreoAPIService.swift` |
| Models | `NetreoDevice.swift`, `NetreoIncident.swift`, `IncidentDetail.swift`, `GroupSummary.swift` |
| ViewModels | `IncidentListViewModel.swift`, `DeviceListViewModel.swift`, `TacticalViewModel.swift` |
| Main views | `DashboardView.swift`, `GroupListView.swift`, `IncidentListView.swift`, `IncidentDetailView.swift`, `SettingsView.swift`, `AutoRefreshButton.swift`, `AutoDiscoveryView.swift` |
| Simple flow | `SimpleContentView.swift`, `SimpleNetreoService.swift`, `SimpleDeviceListView.swift`, `SimpleQuickConfigView.swift`, `DeviceInterfacesView.swift`, `InterfacePerformanceView.swift`, `DeviceLatencyView.swift` |

### Appendix C — References

- BHNM product and API documentation (to be linked when available).
- SwiftUI and Swift concurrency (async/await) for implementation patterns.
- This PRD should be updated when major features are added, when the Simple vs main strategy is decided, or when target BHNM API versions change.

---

*End of PRD. Use this document to align stakeholders and guide the next development cycles.*
