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
- v0.9.0: Duration fixed — widens `startTime` field lookup to cover `incident_open_time` and `open_time`
- v0.9.0: Alarm badge fallback — when middleware cache cold, counts loaded lazily via `getincidentdetail` per row (React Query, `enabled: alarmCounts === null`); shimmer placeholders shown while loading

### Feature: Push Notifications (Web Push)
**Status:** shipped-ios, shipped-pwa
**API:** Middleware `/register-webpush`, `/vapid-key`, `/webhook`

#### Behaviour (both platforms)
- Incident webhook triggers push notification to all registered devices
- Notification shows incident title, body, and severity
- Tapping notification deep-links to incident detail
- Expired/invalid subscriptions cleaned up on 410 Gone

#### iOS-specific
- APNs push delivery (stable long-lived subscriptions, background delivery)
- Custom `benem://` deep-link scheme

#### PWA-specific
- v0.2.0: VAPID Web Push via service worker
- Deep-link via `/incident/{id}` route
- Settings toggle for enable/disable, re-register button
- Requires webhook secret matching BHNM webhook configuration

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
- All four toolbars show the active server name as a subtitle, resolved via `resolveActiveServerName()` with a fallback chain (active-ID match → apiKey+middlewareURL match → sole saved connection → BHNM host → middleware host → "BeNeM"), so the name shows for legacy/migrated/single-server/QR-imported configs, not only when `activeConnectionID` resolves
- `AutoRefreshButton` ring matches the PWA `RefreshRing` proportions (40 px, centered tight monospace M:SS, counter-clockwise drain) but uses iOS-adaptive colors (system track, accent progress arc) instead of the PWA's fixed dark-theme palette

#### PWA-specific
- v0.3.0: React Router NavLink-based tab bar, fixed bottom position
- v0.7.0: Added Settings tab (4 tabs total), persistent on all screens including Settings
- v0.9.0: Unified `AppHeader` component across all 4 screens — connection-status badge (left) · B-icon + screen title + server name (centre) · 40 px `RefreshRing` with M:SS countdown (right; hidden on Settings which has no auto-refresh). `ConnectionBadge` exposes `data-status` attribute for reliable test assertions.

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
- Icon status colour: BHNM list fields when present (`alarm_color` / `status` / `up_status`), else `monitor == 1` → up (BHNM host-checks the device), else unknown. `poll` is **not** consulted — on 26.3.01 it is a runtime poller-state int (0/1/2/5), never a flag. Exact match on `monitor`: an absent or exotic value fails safe to unknown (grey), never to a false green. `devices/list` carries no live state, so "up" means *monitored*; a DOWN host shows the red incident chip beside a green icon until the host_status overlay ships (iOS 2.12.1 / PWA 0.13.1).
- **Planned — Wave B host_status overlay** (spec `docs/superpowers/specs/2026-09-03-host-status-overlay-design.md`, stop-at-design): the middleware's maintenance-map crawl will also serve per-device host `UP`/`DOWN`; the list icon takes the map value when present and falls back to the rule above otherwise. The map is accepted only when `cache_age_seconds` is non-null and ≤ 300 s, decided once at parse time. Honest worst case: a stale colour can persist up to 300 s plus one client hold (PWA ≤ 60 s; iOS ≤ the user's refresh interval, 30–300 s) after the middleware stalls or a device recovers. The icon is BHNM's opinion of host state, not a reachability probe.

#### iOS-specific
- Native SwiftUI List with UID-based identity
- v2.8.0: Device list row redesigned to PWA-parity layout — icon (34 px, status-coloured) + left info column (name / IP / category · site) + right column (5-chip alarm badges + incident ticker). Row compacted: 4 pt vertical padding, 10 pt secondary text.
- v2.8.1: Device list card styling — rows rendered as individual rounded cards matching the Incidents list (`.listStyle(.plain)`, grouped background, horizontal padding). Row padding: 6 pt vertical, 12 pt horizontal.
- Alarm chips use 5 severity colours: green (threshold-based healthy count, `AlarmColor.green.color`) · blue (ack + informational) · yellow (warning, dark text for readability) · orange (major + minor) · red (critical). Zero-count chips show grey outline; green shows "—" when threshold cache not yet loaded.
- Per-row incident ticker reuses `MarqueeText.swift`; shows active incident summaries joined by " · ", sorted critical-first. Fixed-height spacer preserves row height when no incidents are active.
- Category and site names resolved from BHNM list APIs (`restful/category/list`, `restful/site/list`) before device fetch; handles both string IDs (on-prem) and integer IDs (SaaS).

#### PWA-specific
- v0.4.0: Window-based pagination with independent React Query entries per page
- Debounced search input (300ms via useDeferredValue)
- 120-second auto-refresh with RefreshCountdown
- v0.8.0: `DeviceRow` redesigned — `DeviceTypeIcon` (status-coloured, 40 px), alarm badges (green/blue/yellow/orange/red from incident data), scrolling incident ticker at constant speed (visible only when active incidents exist, height preserved when empty)
- v0.10.0+: Category and site names resolved from BHNM list APIs in parallel with device fetch (`fetchNameMap`); handles integer IDs (SaaS) and string IDs (on-prem). Raw numeric ID shown as fallback if resolution fails.

### Feature: Incident Detail
**Status:** shipped-ios, shipped-pwa
**API:** `POST /api/incident_api.php` (method=getincidentdetail)

#### Behaviour (both platforms)
- Fetches full incident detail on open: primary alarms, related alarms, incident state log
- Status section: ACK/UnACK action + status badge + alarm color counts
- Incident Info: ID, title, device, IP, alert type, created timestamp, duration, ACK details when acknowledged
- Primary Alarms: state badge, type, name, output (HTML-stripped), timestamp — hidden when empty
- Related Alarms: same structure, hidden when empty
- Incident State Log: state badge, timestamp, username, comment — hidden when empty
- Duration format: `Xd Xh Xm Xs` (leading zero units omitted)

#### iOS-specific
- Native SwiftUI List layout
- `NetreoAPIService.fetchIncidentDetail` posts to `incident_api.php`

#### PWA-specific
- v0.9.0: `parseIncidentDetailResponse` + `getIncidentDetail` in `src/lib/api/incidents.ts`
- `useIncidentDetail` hook (stale time 60s, keyed by `['incidentDetail', id]`)
- `StateBadge` component for alarm/log state strings (distinct from `StatusBadge` which handles OPEN/ACKD/CLRD on list rows)
- ACK/UnACK invalidates both `['incidents']` and `['incidentDetail', id]` queries

---

### Feature: Device Detail
**Status:** shipped-ios, shipped-pwa
**API:** `POST /fw/index.php?r=restful/devices/find`

#### Behaviour (both platforms)

**Header card** (top of screen, always visible):
- Device name in bold
- IP address below the name (non-bold)
- Category below IP, prefixed with a folder icon
- Site below category, prefixed with a building icon
- Long values scroll horizontally (marquee) rather than truncating
- On iOS: device type icon on the left; latency sparkline occupies the right ~60% of the card when data is available

**Device info card** (collapsible):
- Current state, type of device, model, serial number, SNMP version, UID
- Does **not** repeat device name or IP (shown in header)
- Category and site are shown in the header card, not repeated here

**Screen layout order** (top to bottom):
1. Header card (name, IP, category, site, optional sparkline)
2. Alarm summary bar (H/S/T/A counts)
3. Device info card (collapsible)
4. **Create Maintenance Window** card — full-width tappable card, blue text (`#38bdf8` / sky-400), placed immediately below Current Issues
5. Host Current Issues card (collapsible)
6. Performance charts (expandable per category)

- Host current issues: filtered from incident list by device name; tapping a row navigates to IncidentDetailView
- v2.8.1 (iOS): each incident row in the "HOST CURRENT ISSUES" card is a `NavigationLink` to `IncidentDetailView`; chevron indicator shown automatically
- Inline performance charts: expandable category cards
- Performance data: category discovery → instance filtering → timeseries batch fetch (Last 24 Hours)

#### iOS-specific
- Per-device alarm status via get-host-and-service-status
- Auto-loads latency/CPU on open; mini latency sparkline in header card (right 60%)
- `MarqueeText` component handles horizontal scrolling of long names

#### PWA-specific
- v0.4.0: Info card + filtered incidents using existing useIncidents hook
- v0.5.0: PerformanceSection replaces placeholder; loads on category expand (no auto-load)
- v0.8.0: Full iOS parity for header card and screen layout:
  - Centred device name (h1) + IP above the header card as screen title
  - Header card: `DeviceTypeIcon` (52 px, status-coloured) · info column (category, site, status dot) · `LatencyMiniChart` (eager-loaded, fills remaining width; hidden if no latency data)
  - Alarm summary bar: HEALTHY / ACK / WARNING / CRITICAL counts; greyed out (`text-slate-600`) when zero
  - HEALTHY = `thresholds + ok_enabled_service_checks − active_incidents` (see Threshold Cache feature)
  - Collapsible "Host Information" section (closed by default): Status, Description, Category, Site, Model, Serial, UID
  - Collapsible "Current Issues" section (open by default, badge shows count): severity badge · summary (2-line clamp) · elapsed duration
  - Maintenance Window card placed below the alarm bar (above Host Information)

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

### Feature: Threshold Cache
**Status:** shipped-both
**API:** `GET /api/v1/threshold-counts` (middleware), `POST /fw/index.php?r=restful/devices/list-thresholds-csv` (BHNM, server-side only)

#### Behaviour

- Middleware pre-fetches the BHNM threshold CSV once per `cache_refresh_seconds` interval and parses it server-side into a compact `{deviceName: count}` dictionary
- PWA fetches `GET /api/v1/threshold-counts` — receives ~200 KB JSON regardless of environment size vs ~50 MB raw CSV at 10 K devices
- Falls through to a live BHNM fetch (with server-side CSV parse) if the cache is cold
- Activated by the same per-server `cache_enabled` toggle in the admin portal
- `device_services` endpoint (`/fw/index.php?r=restful/devices/services`) called per-device on the detail screen for enabled+OK service check count

#### Middleware
- `threshold_cache.py` — same asyncio lifecycle as `incident_cache.py` and `tactical_cache.py`
- `GET /api/v1/threshold-counts` — authenticated via `X-Proxy-Token` / `X-BHNM-Target`

#### PWA-specific
- v0.8.0: `useThresholds()` hook (10-min stale time, all devices), `useDeviceServices()` hook (5-min stale time, per device)
- HEALTHY badge in device list rows: `thresholds − active_incidents`
- HEALTHY column in device detail alarm bar: `thresholds + ok_service_checks − active_incidents`

#### iOS-specific
- `ThresholdCache.shared` singleton (`Models/ThresholdCache.swift`); refreshes on `DeviceListViewModel.loadDevices()` and `DeviceDetailViewModel.load()`
- HEALTHY in device list: `max(0, ThresholdCache[name] − activeIncidents)` — shows `—` when cache not yet loaded
- HEALTHY in device detail alarm bar: `max(0, ThresholdCache[name] + okServiceChecks − activeIncidents)`
- `fetchThresholdCounts()` in `NetreoAPIService`: `GET /api/v1/threshold-counts`, proxy-authenticated
- `fetchDeviceServices(deviceName:)` in `NetreoAPIService`: `POST /fw/index.php?r=restful/devices/services`, returns enabled+OK service check count

---

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
**Status:** create — shipped-both · read/display + close — implemented both platforms 2026-09-02 (Rev 3 spec `docs/superpowers/specs/2026-08-31-maintenance-status-read-design.md`)
**API:** Middleware `POST /api/proxy/maintenance/create` → BHNM `POST /api/maint_window_api.php` (create); `POST /api/proxy/maintenance/status` → BHNM `get-host-and-service-status` + `maint_window_api.php action=list` (read); `POST /api/proxy/maintenance/close` → BHNM `action=close` (end/cancel)

The feature has three sides: **create** (set a window), **read/display** (three-state button + blue badge), and **close** (end active or cancel scheduled maintenance from the button, behind a confirmation dialog). The create behaviour is documented first; read + close follow under "Reading maintenance status".

#### Behaviour (both platforms)

**Entry point**
- A full-width tappable card labelled "Create Maintenance Window" with blue text (`#38bdf8` / sky-400) is shown on the device detail screen, immediately below the Host Current Issues card.

**Creating a window**
- User selects a duration and optionally types a note, then taps Create.
- Preset durations: 1 h, 6 h, 12 h, 24 h, 7 d. A "Custom" option allows entering an arbitrary number of minutes (minimum 1).
- The middleware computes (server-side only — a rule change here reaches both
  apps with no client release):
  - `start_time` = **the next 5-minute wall-clock boundary** (`snap_start`); if
    that boundary is <60 s away, the following one (BHNM rejects non-future
    start times). Examples: press 10:00:00 → 10:05:00; 10:05:01 → 10:10:00;
    10:04:59 → 10:10:00.
  - `end_time` = `start_time + (duration_minutes × 60)`
  - The snapped start is echoed to the client in the **`X-Maintenance-Start`**
    response header (epoch); the response body stays a verbatim BHNM
    passthrough. Clients use it for the confirmation copy and the interim
    "Starts at HH:MM" button state.
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
| `start_time` | Unix epoch (`snap_start(now)` — next 5-min boundary, ≥60 s lead) |
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

#### Reading maintenance status + close (implemented — Rev 3)

**Status:** implemented on both platforms, 2026-09-02. Full design + mockups in
`docs/superpowers/specs/2026-08-31-maintenance-status-read-design.md` (Rev 3).
Corrects the old create-spec claim that "no query API exists" — a query path
exists on BHNM 26.3.x.

**Two signals, distinct roles:**
- `inMaintenance` (JSON boolean, host row of `get-host-and-service-status`) is
  the **source of truth** for the badge — it reflects BHNM actually suppressing
  alerts.
- Active windows (`maint_window_api.php action=list`, active-only, `name`
  required) are the **detail** — supply "ends HH:MM" + comment; never decide the
  badge.
- The two can disagree for ~1 poll cycle (~85 s) after a window activates.
  Badge follows `inMaintenance`; not reconciled.

**Middleware:** one merged route `POST /api/proxy/maintenance/status`
(body `name=<device>`) → `{ inMaintenance: bool, windows: [{start_time,
end_time, comment}] }`. Makes both BHNM calls server-side, api_key resolved
server-side (client never sends it), same auth as the create route. Best-effort:
upstream failure → `inMaintenance:false`, empty windows, no 5xx.

**UI (both platforms, v1 = Device Detail only):**
- Header device-status badge shows **MAINTENANCE** (blue,
  `DeviceStatus.maintenance` — the existing enum case wired to a real signal)
  when `inMaintenance == true`, overriding the incident-derived status.
  (PWA `STATUS_COLORS.maintenance` flipped grey → `text-sky-400`.)
- The "Create Maintenance Window" button is **three-state** (precedence:
  `inMaintenance` wins; else a live local pending start; else normal):
  1. **Normal** — unchanged; tap → create sheet/dialog.
  2. **Starts at HH:MM** — blue-tinted outline + clock icon, after a
     successful create (start from `X-Maintenance-Start`). Local knowledge
     only, never persisted; cleared when `inMaintenance` flips, expires ~3 min
     past the start. Tap → *"Cancel scheduled maintenance for `<device>`? The
     window starting at HH:MM will not open."* — **Keep** (default) /
     **Cancel Maintenance** (destructive).
  3. **In Maintenance · ends HH:MM** — filled blue, white text, stop-square
     icon, window comment as caption. Tap → *"End maintenance for `<device>`
     now? Alerting for this device will resume."* — **Cancel** (default) /
     **End Maintenance** (destructive).
- Confirmed close → `POST /api/proxy/maintenance/close` (mirrors create's
  auth; `action=close` passthrough; **ends ALL windows for the device,
  scheduled ones included** — verified live). On success the button clears to
  normal immediately (local suppress, ~3 min) and the status is re-fetched;
  the badge honestly follows one poll later. On failure the state stays and
  the error is surfaced.
- Read is best-effort: on failure, the button falls back to the plain "Create"
  state with no error surfaced. **Version gate:** on BHNM < 26.3.01 the host
  row has no `inMaintenance` key → read as false → normal button, no
  maintenance state ever shown.

**Parity:** identical contract and states on both platforms, same release
wave. iOS: `DeviceDetailViewModel.maintenanceButtonState()` +
`NetreoAPIService.fetchMaintenanceStatus`/`closeMaintenance`. PWA:
`MaintenanceCard.tsx` (`maintenanceButtonState`) + `useMaintenanceStatus`
(60 s React Query) + `fetchMaintenanceStatus`/`closeMaintenanceWindow` in
`src/lib/api/maintenance.ts`.

**Device-list maintenance visibility (implemented 2026-09-02):** blue wrench
beside the name on list + search rows (COEXIST: never masks alarm counts —
the Detail header keeps maintenance-wins per Rev 3) + an "In maintenance (N)"
filter chip, fed by `GET /api/v1/maintenance-map` from the middleware's
`maintenance_cache` (twin of `threshold_cache`; per-category bulk status
calls, paged at 500; empty on cold cache or BHNM < 26.3.01 — no live
fall-through; map refresh fixed at 60 s since middleware 2.9.1). List
staleness: creator sees the wrench instantly (documented local optimism,
8-min expiry, cleared on cancel/close); other viewers ~2–4 min after the
window opens. Detail stays the fresher truth. Spec:
`docs/superpowers/specs/2026-09-02-maintenance-list-badges-design.md`.

**SCHEDULED — next wave, first task (reviewer ruling 2026-09-02, escalated
after the third mirror-verified release): create an iOS XCTest target
(`BeNeMTests`).** The iOS project has no test target, so client logic ships
compiler-+wire-verified only (mirrored from PWA-unit-tested state machines).
First candidates: `maintenanceButtonState`, `snap`-dependent display helpers,
`MaintenanceStatus` parsing, `MaintenanceMapCache` staleness.

---

### Feature: Connection Diagnostics
**Status:** shipped-ios (v2.8.3 dev / middleware 2.7.0, commit `72ec4be`); PWA diagnostics screen shipped alongside (see PWA-specific)
**Criticality:** non-critical / off the delivery path. Fully isolated from proxy/cache/push.
**Design:** `docs/superpowers/specs/2026-09-01-two-hop-diagnostics-design.md` (revised background-monitor design)

#### Behaviour (both platforms)
- **Tap the badge → Diagnostics screen:** a `📱 App → 🖥 Middleware → 🗄 BHNM`
  pipeline with per-hop latency + age (broken red link on a down hop;
  `bhnm.reachable == null` renders as amber "checking", never down); per-feed
  status (Tactical/Incidents/Thresholds: count, age, live vs cached); per-server
  error stats; middleware `/health` readout ("Middleware version" — the
  middleware's own 2.x stream, distinct from the app's version).
- Badge tap-to-refresh is retired on both platforms — refresh lives in the ring.

#### Middleware
- Background **BHNM monitor**: ONE shared `active_probe` loop per servers.json
  entry (`DIAG_PROBE_INTERVAL`, default 15 s; bounded 4 s probe; any HTTP
  response < 500 = alive; down declared after `DIAG_DOWN_THRESHOLD` consecutive
  failures, default 2). `/internal/cache/reload` starts/stops monitor tasks.
- `GET /api/v1/diagnostics` (auth: api_key as `X-Proxy-Token`) only READS the
  monitor's cached result + passive per-feed cache telemetry — never a live
  probe, so it is uniformly fast and safe to poll/fetch on demand. No secrets
  in the payload (counts/booleans/truncated scrubbed errors; host only).

#### iOS-specific
- `ConnectionMonitor`: ONE global 30 s poller (UserDefaults `diag_poll_interval`
  override; 10 s request timeout; foreground-only — pauses on background,
  immediate poll on foreground). Derivation: transport error or non-2xx →
  middleware down; `bhnm.reachable == false` → BHNM down; `null` → checking.
- **Hop-aware banner** under each header: middleware down → "⚠️ Can't reach the
  server · showing last known data · retrying…" (never claims the middleware
  cache); BHNM down (middleware up) → "⚠️ BHNM unreachable · showing cached
  data · retrying…". Pulsing red top edge; reduce-motion → static.
- Recent-call log (last 20 client calls, query strings stripped) in the sheet.

#### PWA-specific
- `/diagnostics` route; badge tap navigates there. The screen fetches
  `/api/v1/diagnostics` **on open + manual refresh only** (no polling, no
  background refetch) — legitimate because the endpoint reads the middleware's
  cached monitor. No recent-call log (iOS-only for now).

#### Named follow-up: PWA connection-status v2 (NOT yet built)
- **PWA global poller + hop-aware banner + badge v2.** The PWA badge still
  derives per-screen from query state (isLoading/isError/dataUpdatedAt), so it
  can read **green off cached middleware responses while BHNM is down** — the
  same masking that iOS v1 had. Parity fix: a global 30 s visible-tab-only
  poller of `/api/v1/diagnostics` driving the badge + a hop-aware banner with
  the same wording as iOS. Until then the PWA badge is transport-level only.

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
- Camera availability check hides button when no camera
- Error states: permission denied, invalid QR, decryption failure
- v0.7.0: Duplicate detection by Server Name + BHNM URL + User Name; QR-scanned servers marked as `isQrProvisioned` with read-only fields
- v0.10.1: Decryption moved server-side — PWA sends blob to `POST /bhnm/api/v1/qr-redeem`; `BENEM_SECRET_KEY` no longer embedded in JS bundle; legacy-format QR codes prompt regeneration
