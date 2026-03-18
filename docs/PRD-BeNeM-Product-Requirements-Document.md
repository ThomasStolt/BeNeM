# BeNeM — Product Requirements Document (PRD)

**Document Version:** 1.0  
**Last Updated:** 2025-03-17  
**Status:** Living document for development guidance  
**Product Name:** BeNeM — Network Management Client for Netreo

---

## 1. Document control

| Version | Date       | Author/Change |
|--------|------------|----------------|
| 1.0    | 2025-03-17 | Initial PRD from codebase analysis |

**Purpose of this document**  
This PRD describes the BeNeM product as understood from the current codebase, and is intended to guide prioritization, feature development, and technical decisions. It follows common product-management practice: problem statement, goals, current state, requirements, and roadmap.

**How to use this PRD**  
- **Product / project owners:** Use for scope, prioritization, and alignment with stakeholders.  
- **Developers:** Use for implementation scope, acceptance criteria, and technical constraints.  
- **QA:** Use for test scenarios and regression focus.  
- **New contributors:** Use as the single source of truth for “what BeNeM is and where it’s going.”

---

## 2. Executive summary

**BeNeM** is a native **network management client** that connects to **Netreo** (on-premises or SaaS) to give users a mobile- or desktop-friendly way to:

- **Monitor** network devices and incidents  
- **View** a dashboard of active incidents and device status  
- **Manage** devices (add, delete; rename supported in API but not yet in UI)  
- **Configure** connection (base URL, API key, PIN, API version, timeouts)

The app is built with **Swift/SwiftUI**, uses a **tab-based** layout (Dashboard, Incidents, Devices, Settings), and supports multiple **Netreo API styles** (legacy PHP, v1, v2, OpenAPI). There is a second, **“Simple”** code path that uses different Netreo REST endpoints and includes device interfaces, interface performance, and latency—but this path is **not** the one launched from the main app entry point today.

**Key takeaway for development:**  
Unify and complete the main flow (real device/incident data, connection test feedback, optional incident acknowledgment), then decide how to integrate or retire the “Simple” path and expose device details (interfaces, performance, latency) through a single, consistent architecture.

---

## 3. Product overview

### 3.1 Vision

BeNeM is the go-to **lightweight client** for Netreo users who want to check network health, triage incidents, and perform basic device management from a phone or tablet without using the full Netreo web UI.

### 3.2 Goals

- **Usability:** Fast, clear access to incidents and devices with minimal configuration (base URL + API key).  
- **Reliability:** Clear connection status and error messages; behavior that degrades gracefully when the Netreo server or API is unavailable.  
- **Flexibility:** Support for different Netreo deployments (legacy PHP APIs, v1/v2/OpenAPI) and optional PIN for SaaS.  
- **Extensibility:** Architecture that allows adding more Netreo capabilities (e.g., acknowledgment, device performance, interfaces) without rewriting the app.

### 3.3 Target users

- **Network operators / NOC staff** who need a quick view of incidents and device status on the go.  
- **IT admins** who manage devices in Netreo and want to add/remove devices from a phone or tablet.  
- **Organizations** already using Netreo who want a dedicated native client instead of the web UI only.

### 3.4 Out of scope (for this PRD)

- Replacing the Netreo web UI for full configuration.  
- Supporting other network management systems (only Netreo).  
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
| API Version       | `netreo_api_version` (legacy/v1/v2/openapi) | NetreoAPIConfiguration |
| Timeout           | `netreo_timeout` (e.g. 10–120 s) | NetreoAPIService |
| Retry Count       | `netreo_retry_count` (e.g. 1–10) | NetreoAPIService |

- **Quick Config (Welcome):** Base URL, API Key, PIN, Test Connection, link to Advanced Settings (Settings sheet).  
- **Settings:** Full form for all of the above; “Test Connection” exists but **only logs to console** (no success/error alert).

### 4.3 Main flow features (ContentView → NetreoAPIService)

| Feature | Implementation | Notes |
|--------|----------------|-------|
| **Dashboard** | `DashboardView` | Status cards (active incidents, total devices); dropdowns to pick incident/device; detail cards for selected incident/device. Data from `IncidentListViewModel` and `DeviceListViewModel`. |
| **Incidents** | `IncidentListView` + `IncidentListViewModel` | List of incidents, severity/status filters (sheet), refresh. No acknowledge action in UI. |
| **Devices** | `DeviceListView` + `DeviceListViewModel` | List, pull-to-refresh, Add (sheet), delete (swipe). Rename exists in ViewModel/API but no UI. |
| **Add device** | `AddDeviceView` | IP, optional name, SNMP community; calls `apiService.addDevice`. |
| **Settings** | `SettingsView` | All connection/API options; Test Connection does not show result to user. |

### 4.4 “Simple” flow (SimpleNetreoService — not main entry)

- Uses Netreo REST-style endpoints (e.g. `/fw/index.php?r=restful/...`).  
- **SimpleContentView:** Connect with server IP + API key → device list; Settings with disconnect.  
- **SimpleDeviceListView:** Device list with refresh; navigation to `DeviceInterfacesView` (placeholder content).  
- **SimpleNetreoService** implements:  
  - Device list (with detailed status), device services, device ID resolution.  
  - Interfaces (performance-instance-per-category and fallbacks; mock if needed).  
  - Interface performance (bandwidth), device latency (with latency instances and data-per-instance).  
- **InterfacePerformanceView** and **DeviceLatencyView** are built for `SimpleNetreoService` (charts, statistics).  
- **DeviceInterfacesView** is currently a placeholder (no real data binding to Simple flow).

### 4.5 Architecture (main flow)

- **UI:** SwiftUI views; tab-based.  
- **State:** `@AppStorage` for config; `@StateObject` / `@ObservedObject` for ViewModels.  
- **ViewModels:** `IncidentListViewModel`, `DeviceListViewModel` (load/refresh, filters, CRUD for devices).  
- **Service layer:** `NetreoAPIService` (single place for Netreo API calls; uses `NetreoAPIConfiguration` and `NetreoEndpoint`).  
- **Models:** `NetreoDevice`, `NetreoIncident`, `DevicePerformance`, `APIResponse`, `DeviceListResponse`, etc.; `AnyCodable` / `DynamicCodingKeys` for flexible API payloads.

### 4.6 API abstraction

- **NetreoAPIConfiguration:** Base URL normalization, API version → path prefix (e.g. `/api/v1`).  
- **NetreoEndpoint:** Enum for device list/add/delete/rename, device info/performance/services, incidents, acknowledgment, categories, sites; each endpoint knows path and HTTP method per version.  
- **NetreoAPIService:** Implements legacy (form-encoded) vs modern (JSON, Bearer) and version-specific paths.

### 4.7 Data models (summary)

- **NetreoDevice:** ip, name, hostname, status (up/down/warning/critical/unknown/maintenance), deviceType, lastUpdated, siteID, categoryID, snmpCommunity, isActive, additionalProperties.  
- **NetreoIncident:** incidentID, deviceIP/deviceName, summary, description, severity (critical→informational), status (active/acknowledged/resolved/closed), category, startTime, acknowledgedTime, resolvedTime, acknowledgedBy.  
- **DevicePerformance:** deviceIP, timestamp, metrics (e.g. cpu/memory/disk/network); used in model but **fetchDevicePerformance** is a stub (returns empty array).

---

## 5. Functional requirements

### 5.1 Current (as-implemented) requirements

These are treated as the baseline “must preserve” behavior.

| ID | Requirement | Priority |
|----|-------------|----------|
| F1 | User can set Netreo base URL, API key, and optional PIN and persist them. | P0 |
| F2 | User can select API version (legacy, v1, v2, openapi) and adjust timeout/retry. | P1 |
| F3 | When configured, user sees Dashboard, Incidents, and Devices tabs. | P0 |
| F4 | Dashboard shows counts of active incidents and total devices and allows selecting an incident or device to show details. | P0 |
| F5 | Incidents list shows severity and status; user can filter by severity and status and refresh. | P0 |
| F6 | Device list supports refresh; user can add a device (IP, optional name, SNMP community) and delete a device (swipe). | P0 |
| F7 | Settings screen exposes all connection and API options. | P0 |

### 5.2 Intended (to be implemented) requirements

| ID | Requirement | Priority | Notes |
|----|-------------|----------|-------|
| F8 | User can run “Test Connection” and see a clear success or error message (alert or inline). | P0 | Currently only console log. |
| F9 | Device list shows real devices from Netreo API (no mock data in production path). | P0 | Current implementation returns mock devices in both legacy and modern paths. |
| F10 | Incident list shows real incidents from Netreo API for the configured endpoint/version. | P0 | Already implemented for incidents; ensure parity across versions. |
| F11 | User can acknowledge an incident from the app (if Netreo API supports it). | P1 | Endpoint exists; UI not implemented. |
| F12 | User can rename a device from the device list or detail (API/ViewModel already support it). | P2 | Add UI (e.g. context menu or edit screen). |
| F13 | Optional: Device detail view with performance metrics when API provides them. | P2 | Unblock by implementing or wiring `fetchDevicePerformance`. |
| F14 | Optional: Device interfaces and interface performance (align with Simple flow or migrate Simple features into main flow). | P2 | Requires design: reuse SimpleNetreoService vs extend NetreoAPIService. |

### 5.3 Edge cases and error behavior

- **Empty/missing config:** Show Welcome + Quick Config; no Dashboard/Incidents/Devices until base URL and API key are set.  
- **Connection failure:** All list/dashboard loads should surface a user-visible error (e.g. in ViewModel `errorMessage` or alert).  
- **API version mismatch:** Document supported Netreo versions per API type; show clear error if server responds with failure or unexpected format.  
- **Partial data:** Incidents and devices should tolerate missing optional fields (e.g. device name, incident description) without crashing.

---

## 6. Non-functional requirements

| ID | Category | Requirement |
|----|----------|-------------|
| NFR1 | Performance | Dashboard and lists should load within a few seconds on typical networks; use async/await and avoid blocking the main thread. |
| NFR2 | Security | API key and PIN must not be logged or exposed in UI beyond secure fields; use SecureField for secrets where appropriate. |
| NFR3 | Compatibility | Support the Netreo API versions and endpoint shapes currently abstracted (legacy, v1, v2, openapi). |
| NFR4 | Maintainability | Prefer a single service layer (e.g. NetreoAPIService) and shared models for all Netreo data; avoid duplicate logic between “main” and “Simple” flows long term. |
| NFR5 | Accessibility | Use semantic labels and support Dynamic Type and VoiceOver where applicable. |
| NFR6 | Offline / poor connectivity | Show last known data and clear “connection failed” state; avoid silent failures. |

---

## 7. Gaps and technical debt

### 7.1 Critical (should fix soon)

1. **Device list returns mock data**  
   In `NetreoAPIService`, both `performLegacyDeviceRequest` and `performModernDeviceRequest` return `createMockDevices()` instead of parsing the real API response. Real device parsing must be implemented and mock only used for tests or fallback.

2. **Test Connection has no user feedback**  
   In `SettingsView`, `testConnection()` only prints success/failure to the console. Add an alert or inline message showing result (and, on failure, error message).

3. **Debug logging in production path**  
   Remove or guard `print(...)` in `IncidentListView`, `IncidentListViewModel`, and API/incident parsing so they do not run in release builds (or use a proper logging framework with levels).

### 7.2 Important (improve when touching related code)

4. **Duplicate “Simple” vs main flow**  
   Two parallel implementations: main flow (NetreoAPIService + Dashboard/Incidents/Devices) and Simple flow (SimpleNetreoService + device list, interfaces, performance, latency). Decide: merge capabilities into one service and one navigation, or clearly separate (e.g. build flavor) and document.

5. **DeviceInterfacesView is placeholder**  
   When navigated to from Simple device list, it shows static text. Either wire it to SimpleNetreoService interface data or remove the navigation until the feature is implemented in the chosen flow.

6. **fetchDevicePerformance is a stub**  
   Returns `[]`; either implement against Netreo API or remove from public API until ready.

7. **Incident acknowledgment**  
   Backend endpoint exists in `NetreoEndpoint.acknowledgment`; no UI to acknowledge. Add when prioritizing incident management.

### 7.3 Nice to have

8. **Rename device UI**  
   ViewModel and API support rename; add a row action or edit screen.  
9. **Unified error handling**  
   Centralize API errors and user-facing messages (e.g. via a small error-handling helper or environment object).  
10. **Connection test in Quick Config**  
   QuickConfigView already shows connection result in an alert; ensure Settings uses the same pattern for consistency.

---

## 8. Roadmap and prioritization

Suggested order of work for the next phases:

### Phase 1 — Stabilize and complete core (P0)

- Implement real device list parsing in `NetreoAPIService` (replace mock in production path).  
- Add user-visible result for “Test Connection” in Settings (alert or inline).  
- Remove or gate debug prints in incidents/list views and API.  
- Ensure incident list and dashboard use real data and show errors clearly.

### Phase 2 — Quality and UX (P1)

- Add incident acknowledgment UI where Netreo API supports it.  
- Improve error messages and offline/error state across Dashboard, Incidents, Devices.  
- Optional: Add unit tests for ViewModels and API parsing (e.g. device/incident decoding).

### Phase 3 — Feature parity and cleanup (P2)

- Add device rename UI.  
- Decide strategy for “Simple” flow: integrate interfaces/performance/latency into main flow via NetreoAPIService (or a shared service), or keep as separate build and document it.  
- Implement or explicitly defer `fetchDevicePerformance` and device/interface detail screens.  
- Replace or supplement ad-hoc logging with a simple logging utility (e.g. OSLog) and use it in Service/ViewModels.

### Phase 4 — Enhancements (backlog)

- Device detail with performance charts.  
- Interface list and interface performance in main flow.  
- Latency view in main flow.  
- Accessibility pass (labels, Dynamic Type, VoiceOver).  
- Optional: Support multiple saved Netreo servers (e.g. list of configs and switch).

---

## 9. Success criteria

- **Phase 1:** Users see real devices and incidents; connection test gives clear feedback; no mock device data in production; no unnecessary console noise in release.  
- **Phase 2:** Users can acknowledge incidents when the API allows it; errors are visible and understandable.  
- **Phase 3:** Device rename is available; strategy for Simple vs main flow is decided and documented; performance/interface/latency either integrated or explicitly scoped for a later release.

---

## 10. Appendices

### Appendix A — Glossary

| Term | Definition |
|------|------------|
| Netreo | Network monitoring and management platform (on-prem or SaaS). |
| BeNeM | This client app: “Network Management Client for Netreo.” |
| Legacy API | Netreo PHP-style APIs (e.g. form-encoded POST to `/devices/list`, `/api/incident_api.php`). |
| Modern API | Netreo v1/v2/OpenAPI REST-style APIs (JSON, Bearer auth). |
| Main flow | ContentView → NetreoAPIService → Dashboard, Incidents, Devices. |
| Simple flow | SimpleContentView → SimpleNetreoService → device list, interfaces, performance, latency (not used by default entry point). |

### Appendix B — File and component reference

| Area | Key files |
|------|------------|
| App entry | `BeNeMApp.swift`, `ContentView.swift` |
| Config / API | `NetreoAPIConfiguration.swift`, `NetreoAPIService.swift`, `NetreoEndpoint` (in config) |
| Models | `NetreoDevice.swift`, `NetreoIncident.swift` (and related in same file) |
| ViewModels | `IncidentListViewModel.swift`, `DeviceListViewModel.swift` |
| Main views | `DashboardView.swift`, `IncidentListView.swift`, `DeviceListView.swift`, `SettingsView.swift`, `QuickConfigView.swift`, `AddDeviceView.swift` |
| Simple flow | `SimpleContentView.swift`, `SimpleNetreoService.swift`, `SimpleDeviceListView.swift`, `SimpleQuickConfigView.swift`, `DeviceInterfacesView.swift`, `InterfacePerformanceView.swift`, `DeviceLatencyView.swift` |

### Appendix C — References

- Netreo product and API documentation (to be linked when available).  
- SwiftUI and Swift concurrency (async/await) for implementation patterns.  
- This PRD should be updated when major features are added, when the “Simple” vs main strategy is decided, or when target Netreo API versions change.

---

*End of PRD. Use this document to align stakeholders and guide the next development cycles.*
