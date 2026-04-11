# BeNeM Feature Specification

This is the canonical feature list for BeNeM. Both `ios/` and `pwa/` implement
features defined here. Platform-specific behaviour is noted per feature.

## Feature template

### Feature: [Name]
**Status:** planned | in-progress | shipped-ios | shipped-pwa | shipped-both
**API:** [endpoint(s) used]

#### Behaviour (both platforms)
-

#### iOS-specific
-

#### PWA-specific
-

---

## Features

### Feature: Incident List
**Status:** shipped-ios, shipped-pwa
**API:** `GET /api/v1/incidents` (cached, enriched) with fallback to `POST /api/incident_api.php` (method=getincidents)

#### Behaviour (both platforms)
- Display open incidents with alarm color badges (red/orange/yellow/green/blue)
- Incidents and alarm counts load in a single response via middleware cache
- Swipe gestures for acknowledge / unacknowledge
- Pull-to-refresh and 120-second auto-refresh
- Navigate to incident detail on tap
- Dashboard ticker shows latest 3 open critical/major incidents (excludes ALARMS CLEARED)
- Fallback: if cache is cold, incidents load from BHNM directly; alarm counts load per-incident

#### Middleware Cache
- Background loop per enabled BHNM server pre-fetches `getincidents` + `getincidentdetail` per incident
- Enriches each incident with `alarm_counts` and `alert_type` before storing in memory
- API calls paced evenly over configurable refresh interval (60-900s, default 120s) to avoid BHNM overload
- Admin portal toggle to enable/disable caching per server; triggers `/internal/cache/reload`
- Server resolved by `X-Proxy-Token` (api_key) or `X-BHNM-Target` (BHNM URL) header

#### iOS-specific
- `fetchCachedIncidents()` in `NetreoAPIService` calls `GET /api/v1/incidents`
- Falls back to legacy `fetchIncidents()` + per-incident `loadAlarmCounts()` if cached endpoint fails
- SwiftUI `List` with native swipe actions (right = ACK, left = UnACK)
- Auto-refresh countdown ring in the toolbar (`AutoRefreshButton`)

#### PWA-specific
- `getCachedIncidents()` in `lib/api/incidents.ts` calls `GET /api/v1/incidents` via `fetchJson`
- Falls back to legacy `getIncidents()` POST if cached endpoint fails
- Alarm color badges rendered via `AlarmBadges` component
- v0.1.0: read-only list, 120s auto-refresh, pull-to-refresh, tap navigates to detail stub
- v0.1.0.5: hosted at `https://benem.hurrikap.org` as a dedicated container alongside the middleware; minimal Settings screen for BHNM API key entry (localStorage)
- v0.1.1: real incident detail screen (essentials: metadata + ACK action), swipe ACK/UnACK on list rows, polished Settings with PIN + test-connection via ha_status endpoint
- Pull-to-refresh is hand-rolled in `components/PullToRefresh.tsx`; row swipe gestures use `react-swipeable`

### Feature: Push Notifications (Web Push)
**Status:** shipped-ios, shipped-pwa
**API:** Middleware `/register-webpush`, `/vapid-key`, `/webhook`

#### Behaviour (both platforms)
- Incident webhook triggers push notification to all registered devices
- Notification shows incident title, body, and severity
- Tapping notification deep-links to incident detail
- Expired/invalid subscriptions cleaned up on 410 Gone

#### iOS-specific
- APNs with Time Sensitive entitlement support
- Custom `benem://` deep-link scheme

#### PWA-specific
- v0.2.0: VAPID Web Push via service worker
- Deep-link via `/incident/{id}` route
- Settings toggle for enable/disable, re-register button
- Requires webhook secret matching BHNM webhook configuration
- No Time Sensitive / Critical Alerts (Web Push API limitation)

### Feature: Dashboard (Tactical Overview)
**Status:** shipped-ios, shipped-pwa
**API:** `POST /fw/index.php?r=restful/tactical-overview/data`

#### Behaviour (both platforms)
- Aggregate H/S/T/A status counts (hosts, services, thresholds, anomalies)
- Color-coded status cards (OK/ACK/WARN/UN/CRIT)
- Incident ticker showing critical and major incidents
- Auto-refresh every 120 seconds with countdown indicator
- Drill-down links to category, site, and business workflow views (v0.4.0)

#### iOS-specific
- Native SwiftUI cards with SF Symbols

#### PWA-specific
- v0.3.0: Dashboard screen as default route, status cards, horizontal auto-scrolling incident ticker
- v0.7.0: iOS-style redesign — summary cards (Active Incidents + Total Devices), step-through incident ticker with slide animation and page dots, iOS-style heat map status cards, full-width drill-down rows with icons, chain-link connection badge, circular refresh ring

### Feature: Navigation (Tab Bar)
**Status:** shipped-ios, shipped-pwa

#### Behaviour (both platforms)
- Bottom tab bar with Dashboard, Incidents, Devices, Settings tabs
- Persistent across all screens
- Active tab highlighting

#### iOS-specific
- Native UITabBarController / SwiftUI TabView

#### PWA-specific
- v0.3.0: React Router NavLink-based tab bar, fixed bottom position
- v0.7.0: Added Settings tab (4 tabs total), persistent on all screens including Settings

### Feature: Multi-Server Management
**Status:** shipped-ios, shipped-pwa

#### Behaviour (both platforms)
- Add, edit, delete, and switch between multiple BHNM servers
- Active server indicator
- Per-server push notification configuration
- Legacy single-server config migration (one-time)

#### iOS-specific
- AppStorage-based server list

#### PWA-specific
- v0.3.0: localStorage `benem_servers` JSON array, legacy key migration from v0.2.0 format
- Settings redesigned with server list section and per-server add/edit form
- v0.7.0: iOS settings parity — QR-scanned servers lock fields to read-only (except Server Name and Push toggle), added User Name (ackUser), BHNM URL, and Middleware URL fields, single Save button that tests then saves, server switch confirmation dialog, delete button with confirmation

### Feature: Device List
**Status:** shipped-ios, shipped-pwa
**API:** `POST /fw/index.php?r=restful/devices/list`, `POST /fw/index.php?r=restful/devices/find`

#### Behaviour (both platforms)
- Paginated device list (50 per page) with Previous/Next controls
- Server-side search by device name
- Display device name, IP, category badge per row
- Tap navigates to device detail

#### iOS-specific
- Native SwiftUI List with UID-based identity

#### PWA-specific
- v0.4.0: Window-based pagination with independent React Query entries per page
- Debounced search input (300ms via useDeferredValue)
- 120-second auto-refresh with RefreshCountdown

### Feature: Device Detail
**Status:** shipped-ios, shipped-pwa
**API:** `POST /fw/index.php?r=restful/devices/find`

#### Behaviour (both platforms)
- Device info card: IP, model, serial number, category, site, description
- Host current issues: filtered from incident list by device name
- Inline performance charts (v0.5.0): expandable category cards with Recharts line/area charts
- Performance data: category discovery → instance filtering → timeseries batch fetch (Last 24 Hours)

#### iOS-specific
- Per-device alarm status via get-host-and-service-status
- Auto-loads latency/CPU on open; mini header sparkline

#### PWA-specific
- v0.4.0: Info card + filtered incidents using existing useIncidents hook
- v0.5.0: PerformanceSection replaces placeholder; loads on category expand (no auto-load)
- Alarm status badges deferred (no per-device H/S/T/A endpoint identified)

### Feature: Tactical Drill-down
**Status:** shipped-ios, shipped-pwa
**API:** `POST /fw/index.php?r=restful/tactical-overview/data`

#### Behaviour (both platforms)
- Category, Site, and Business Workflow group list views
- Per-group H/S/T/A alarm count badges (OK/ACK/WARN/UN/CRIT)
- Filter toggle to hide all-healthy groups
- 120-second auto-refresh

#### iOS-specific
- Native SwiftUI grouped list

#### PWA-specific
- v0.4.0: Single parameterized TacticalGroupListScreen for all three group types
- Filter button in header with active state indicator

### Feature: Performance Charts
**Status:** shipped-ios, shipped-pwa
**API:** `POST /fw/index.php?r=restful/devices/performance-category`, `POST /fw/index.php?r=restful/devices/performance-instance-per-category`, `POST /fw/index.php?r=restful/devices/timeseries-metrics`

#### Behaviour (both platforms)
- Category-based metric discovery per device (CPU, Memory, Disk, Latency, Network, etc.)
- Instance filtering: removes per-process metrics, swap, raw-byte duplicates
- Timeseries batch fetch by statGroup + unit (Last 24 Hours, 5-minute polling)
- Interface metrics produce dual in/out series (value1/value2)
- Empty-unit handling: uses metric title as metricFilterUnits (with overrides)

#### iOS-specific
- Auto-loads latency and CPU categories on device detail open
- Mini sparkline in device header (latency)
- SwiftUI charts with per-instance expandable cards

#### PWA-specific
- v0.5.0: Inline PerformanceSection in DeviceDetailScreen
- Expandable MetricCard per category; loads on expand (no auto-load)
- Recharts AreaChart (single series) / LineChart (multi-series) with dark theme
- React Query hooks: 5-min stale for categories/instances, 60s for timeseries

### Feature: Maintenance Windows
**Status:** shipped-pwa
**API:** Middleware `POST /api/proxy/maintenance/create` → BHNM `POST /api/maint_window_api.php`

#### Behaviour (both platforms)

**Creating a window**
- User selects a duration and optionally types a note, then taps Create.
- Preset durations: 1 h, 6 h, 12 h, 24 h, 7 d. A "Custom" option allows entering an arbitrary number of minutes (minimum 1).
- The middleware computes:
  - `start_time` = `now + 900` (UTC epoch seconds — 15 minutes in the future, matching BHNM's expectation)
  - `end_time` = `start_time + (duration_minutes × 60)`
- The middleware posts to BHNM with `action=new`, `name` (device name), `start_time`, `end_time`, `comment`, and `password` (api_key resolved server-side — the client does **not** send the key).
- On success BHNM returns `{"result":"success"}`. On failure it returns `{"result":"error","detail":"..."}`, which the middleware surfaces as HTTP 200 with an error body (not a 5xx); the client checks `result === "error"` and shows the message.

**Description / comment field**
- The description is always prefixed with a **non-editable** stamp:
  ```
  Created by <ackUser> on YYYY-MM-DD HH:MM: 
  ```
  - `<ackUser>` is the "User Name" field from the active server configuration (falls back to `"unknown"` if blank).
  - Timestamp is the **local wall-clock time** at the moment the dialog opens (not at submit), formatted `YYYY-MM-DD HH:MM` (zero-padded, 24 h).
  - The trailing `: ` (colon + space) is part of the prefix so the optional user note reads naturally.
- The user may type additional free text after the prefix. This portion is optional.
- **Hard limit: the full comment string (prefix + user note) must not exceed 255 characters.** The editable field enforces `maxLength = 255 − prefix.length`. A character counter is shown; it turns amber when ≤ 20 characters remain.

**Middleware proxy contract**

Client → middleware (`POST /api/proxy/maintenance/create`, form-encoded):

| Field | Type | Notes |
|---|---|---|
| `name` | string | Device name (required) |
| `duration` | integer | Duration in minutes ≥ 1 (required) |
| `comment` | string | Full comment string, max 255 chars |

Authentication: `X-Proxy-Token` header (webhook secret) or `X-BHNM-Target` header. The middleware resolves the BHNM api_key server-side; the client never sends it.

Middleware → BHNM (`POST /api/maint_window_api.php`, form-encoded):

| Field | Value |
|---|---|
| `password` | BHNM api_key (resolved by middleware) |
| `action` | `new` |
| `name` | device name |
| `start_time` | Unix epoch (now + 900 s) |
| `end_time` | Unix epoch (start_time + duration_minutes × 60) |
| `comment` | full comment string |

**Important:** the middleware strips the client's `Content-Length` header before forwarding its own body to BHNM, because the body is reconstructed (not forwarded verbatim). Failing to do this causes `h11 LocalProtocolError: Too much data for declared Content-Length`.

#### iOS-specific
- Show a sheet or modal from the Device Detail screen with the same fields.
- Username: read from the `ackUser` property of the active `BHNMServer` configuration.
- Build the non-editable prefix using `DateFormatter` or `String(format:)` with local calendar; match format `YYYY-MM-DD HH:MM` (24 h, zero-padded).
- Enforce the 255-character total limit: compute `maxLength = 255 - prefix.count` and apply it to the `TextField` / `UITextField`.
- Show a character counter label; highlight it (e.g. orange) when ≤ 20 characters remain.
- Call `NetreoAPIService.createMaintenanceWindow(deviceName:durationMinutes:comment:)` (to be implemented), which posts to `/api/proxy/maintenance/create`.
- The success/error response JSON from BHNM is proxied verbatim; check `result == "success"` vs `result == "error"`.

#### PWA-specific
- `MaintenanceDialog` component (`src/features/devices/MaintenanceDialog.tsx`).
- `username` prop comes from `config.ackUser` (via `useConfig()`).
- `buildPrefix(username)` constructs the stamp at dialog open time (captured in component state via `isOpen` guard).
- Comment submitted as `prefix + userComment`.
- API call via `createMaintenanceWindow()` in `src/lib/api/maintenance.ts`.

---

### Feature: QR Server Onboarding
**Status:** shipped-ios, shipped-pwa

#### Behaviour (both platforms)
- Scan `benem://configure` QR codes to add/update server configuration
- AES-256-GCM encryption (shared key across platforms)
- Compact format: single encrypted JSON blob with all fields
- Legacy format: individual encrypted parameters
- Duplicate detection; offers update instead of add

#### iOS-specific
- Native AVFoundation camera scanner in QRScannerView
- `benem://` URL scheme handler in BeNeMApp + DeepLinkHandler

#### PWA-specific
- v0.5.0: html5-qrcode camera overlay from Settings
- Web Crypto API for AES-256-GCM decryption
- Encryption key via VITE_QR_ENCRYPTION_KEY build env var (mapped from BENEM_SECRET_KEY at Docker build time)
- Camera availability check hides button when no camera
- Error states: permission denied, invalid QR, decryption failure
- v0.7.0: Duplicate detection by Server Name + BHNM URL + User Name; QR-scanned servers marked as `isQrProvisioned` with read-only fields
