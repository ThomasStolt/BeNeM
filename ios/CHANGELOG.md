# Changelog

All notable changes to BeNeM are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **Note:** BMC Helix Network Management (BHNM) was formerly known as **Netreo**. Internal code identifiers still use the legacy `Netreo` prefix for backwards compatibility.

---

## [Unreleased]

---

## [2.8.0] — 2026-05-15

### Added

- **Device list PWA-parity row layout** — each row now shows a status-coloured icon, a left info column (name / IP / category · site), and a right column with 5-chip alarm badges plus a scrolling incident ticker. Replaces the previous HEALTHY / ACK / WARNING / CRITICAL badge strip.
- **5-chip alarm badges** — green (healthy = thresholds − active incidents), blue (acknowledged + informational), yellow (warning severity), orange (major + minor), red (critical). Zero-count chips show a grey outline. Green shows "—" while the threshold cache is loading.
- **Per-row incident ticker** — active incident summaries scroll horizontally below the chips (critical-first, joined by " · ") reusing `MarqueeText.swift`. A fixed-height spacer keeps row height stable when no incidents are active.

### Changed

- **Device row compacted** — icon 40 → 34 px, vertical padding 6 → 4 pt, secondary text 11 → 10 pt, tighter internal spacing throughout.
- **Green chip colour** — uses `AlarmColor.green.color` (forest green, consistent with the home screen and incident list) instead of SwiftUI's system green.

### Fixed

- **Category / site names on SaaS BHNM** — `ensureCategoryCache` and `ensureSiteCache` now accept integer IDs (returned by SaaS-hosted BHNM) in addition to string IDs (on-prem); device rows now show human-readable category and site names on both deployment types.
- **ThresholdCache case-insensitive lookup** — `ThresholdCache.count(for:)` uses `caseInsensitiveCompare` so device names differing only in case correctly resolve to their threshold count.
- **fetchThresholdCounts nested dict** — the middleware wraps threshold data as `{"cache_age_seconds": N, "counts": {...}}`; the parser now reads the nested `counts` dict instead of the top-level object (which returned 0 for every device).

---

## [2.7.0] — 2026-04-12

### Added

- **Alarm badge strip on device list rows** — each device row now shows a HEALTHY / ACK / WARNING / CRITICAL badge strip derived from the global incident list and the new threshold cache; HEALTHY shows `—` until the cache warms
- **ThresholdCache** — new `@MainActor` singleton (`Models/ThresholdCache.swift`) fetches `GET /api/v1/threshold-counts` from the middleware once every 10 minutes; cache is invalidated automatically when the active server changes
- **Real HEALTHY count in device detail** — alarm bar now computes `max(0, thresholds + ok_service_checks − active_incidents)` using the threshold cache and a new `fetchDeviceServices()` API call; replaces the old binary 0/1 formula
- **Active server name subtitle** — all four tab toolbars (Home, Incidents, Devices, Settings) now show the active server's human-readable name below the screen title; updates instantly on server switch
- **Settings: ConnectionBadge** — the Settings toolbar now shows the chain-link connection indicator on the left, matching the other three tabs
- **M:SS countdown in AutoRefreshButton** — the circular ring now displays the remaining time as `M:SS` text inside the ring (e.g. `1:38`); the ring starts full and drains counter-clockwise, replacing the static arrow icon
- **Settings: radio-circle server select** — the passive green dot is replaced by a tappable 22 px circle: filled blue with checkmark when active, empty outline when inactive; tapping the circle opens the switch dialog; tapping the server name navigates to edit for all rows
- **Settings: inline delete with confirmation** — each server row has a trash icon; first tap turns it red and shows "Delete?"; second tap deletes the server; attempting to delete the active server shows a blocking alert

### Changed

- **QR import no longer auto-switches active server** — scanning a `benem://` QR code adds the server to the list without activating it; the user must switch manually via the radio-circle button
- **Middleware URL is always required** — middleware URL is now in the Connection section of server configuration (not the Push section) and is a mandatory field; the app never connects directly to BHNM; the direct-BHNM fallback in `ContentView` is removed

### Fixed

- **Middleware URL guard order** — the empty-guard in `ServerConfigView` now fires on the raw trimmed string before `https://` prefix injection, preventing the guard from always passing on empty input
- **Middleware URL preserved when push disabled** — toggling off push notifications no longer blanks the stored middleware URL
- **Proxy token header suppressed when webhook secret is empty** — `X-Proxy-Token` is only sent when a webhook secret is configured
- **ThresholdCache invalidated on server switch** — switching servers immediately invalidates the threshold cache so stale counts from the previous server are never shown
- **Server name subtitle shown on cold launch** — `netreo_active_connection_name` is now written in `updateAPIService()` (called on `.onAppear`) in addition to `handleConnectionChange`, so the subtitle appears correctly without requiring a server switch

---

## [2.6.0] — 2026-04-07

### Security

- **Keychain credential storage** — API keys, PINs, and webhook secrets are now stored in the iOS Keychain (`Security.framework`) instead of `UserDefaults`. Existing plaintext values are migrated transparently on first load. New `KeychainHelper` utility wraps `SecItemAdd`/`SecItemCopyMatching`/`SecItemDelete`.
- **App Transport Security tightened** — replaced `NSAllowsArbitraryLoads = true` with `NSAllowsLocalNetworking = true` in `Info.plist`. All non-local HTTP traffic now requires valid TLS certificates.
- **Deep link URL validation** — `DeepLinkHandler` now rejects `benem://` payloads where `middleware_url` uses a non-HTTP(S) scheme, preventing scheme-based injection.

---

## [2.5.0] — 2026-04-03

### Added

- **3-column device header** — the device detail header now shows the device icon, info (name, IP, category, site), and a mini latency line chart side by side; the chart shows the last 24 hours with auto-scaled Y axis and the most recent value
- **Scrolling device name** — long device names in the header card now scroll horizontally (MarqueeText) instead of truncating
- **CPU Cores combined chart** — CPU core metrics are rendered as a single multi-line chart with up to 4 cores, each in a distinct color, with core names from BHNM (e.g. `.0.0 #196608`) and auto-scaled Y axis
- **Batch time-series fetch** — new `fetchTimeSeriesBatch()` API method fetches multiple related metrics (e.g. all CPU cores) in a single API call, splitting results by `instanceDescr`
- **Empty-unit metric support** — metrics with no unit from discovery (e.g. Running Processes, System Load) now send the correct `metricFilterUnits` value via an override map

### Changed

- **Latency moved to Performance** — latency is no longer a standalone section; it appears as the first group inside the PERFORMANCE card, sorted automatically
- **Time-series API upgraded** — all metric fetching now uses the high-performance `timeseries-metrics` endpoint; removed dead code for the legacy `get-time-series-metrics` endpoint

### Fixed

- **CPU Cores showing fewer than expected** — individual per-core API calls raced and dropped results; replaced with a single batch fetch that reliably returns all cores
- **CPU Cores chart garbled** — chart lines were not separated by series; fixed by using `foregroundStyle(by:)` with a color scale mapping

---

## [2.4.0] — 2026-04-02

### Added

- **QR code scanner** — new "Scan QR" button in Settings alongside "Add Manually"; opens a full-screen camera view to scan `benem://` configuration QR codes generated by the admin portal. Camera permission is requested on first use with a fallback prompt linking to iOS Settings.
- **Floppy disk Save icon** — custom-drawn floppy disk icon (`FloppyDiskIcon`) on the Save button in server configuration, green when changes are pending, greyed out when nothing has changed.
- **Trash icon on Delete** — Delete button now shows a red trash icon for clearer affordance.

### Changed

- **Save button disabled when no changes** — the Save button in server configuration is greyed out when all fields match the saved values, preventing unnecessary save/test cycles.
- **Tab bar hides on keyboard** — the custom tab bar slides out when the keyboard appears and returns when it dismisses, preventing it from covering input fields.
- **Tap-to-dismiss keyboard** — tapping the form background in server configuration dismisses the keyboard.
- **Settings tab always resets to root** — switching to the Settings tab from any other tab pops back to the root settings screen instead of preserving a pushed server configuration view.
- **Immediate data clear on server switch** — switching servers resets all navigation stacks and clears cached incidents, devices, and tactical data immediately instead of waiting for the next refresh cycle.

---

## [2.3.2] — 2026-03-27

### Changed

- **Tactical pre-loading reduced** — Sites and Business Workflows no longer pre-load in the background on every Dashboard refresh; they load on demand when the user navigates to them. Categories still pre-loads alongside incidents and devices (required for the Dashboard H/S/T/A stat boxes).
- **Alarm count fetching serialised** — incident alarm counts are now fetched one at a time instead of all concurrently, preventing large bursts of parallel requests to the proxy when there are many active incidents.

---

## [2.3.1] — 2026-03-27

### Fixed

- **Form encoding in device add/rename/delete** — `addDevice`, `renameDevice`, and `deleteDevice` now use `URLQueryItem`-based percent-encoding (same as all other endpoints) instead of naive string interpolation; API keys or device names containing `+`, `=`, `&`, or `%` no longer get corrupted on the wire
- **Tactical overview drops service/threshold-only groups** — groups with zero host counts but non-zero service, threshold, or anomaly alarms were silently filtered out; they now appear correctly
- **`loadAlarmCounts` fired on network error** — alarm color counts were re-fetched even when the preceding incident fetch failed, amplifying errors under poor connectivity; counts are now only refreshed after a successful fetch
- **ACK/UnACK ignores API-level failures** — a BHNM response of HTTP 200 with `"success": false` was treated as a successful acknowledgement; the body is now inspected and the failure is correctly surfaced to the UI
- **Alarm filter missing anomaly alarms** — the funnel filter in Categories / Sites / Business Workflows hid groups whose only non-green counts were in the Anomalies (A) column; anomalies are now included in the `hasAlarms` check per spec
- **Deep link buffer truncation** — `zlibDecompress` allocated a fixed 8× output buffer; if the decompressed payload exceeded that size the output was silently truncated and the link failed with an opaque error; the function now detects buffer exhaustion and throws a clear error

---

## [2.2.0] — 2026-03-27

### Changed

- **API Proxy Middleware** — all BHNM API calls now route through the `bhnm-apns` middleware; the "Server URL" field is renamed **"Middleware URL"** and must point to your middleware instance (e.g. `https://bhnm-apns.yourcompany.com`). This allows BHNM servers on private networks to be reached from anywhere
- **Webhook Secret now required** — the Webhook Secret field is always shown and must be filled in before a connection can be saved; it authenticates both push notification registration and all proxied API requests (`X-Proxy-Token`)
- **Push Notifications section simplified** — the "Enable Push Notifications" toggle is removed; push and proxy authentication now share a single secret field

### Added

- **`X-Proxy-Token` header** — injected automatically on every outgoing API request using the configured Webhook Secret

### Removed

- **Auto Discovery** — the local Wi-Fi SNMP scanner has been removed; middleware URLs cannot be discovered on the LAN, so the feature no longer applies
- **`--push-url` flag** — removed from `generate_benem_link.py`; the middleware URL is now the connection's base URL

### Migration

Existing users must:
1. Pull and redeploy `bhnm-apns` (`./upgrade.sh` on the server), then add `BHNM_URL` and `PROXY_SECRET` to `.env`
2. Edit each saved connection: set **Middleware URL** to the middleware address and ensure a **Webhook Secret** is set
3. Regenerate any `benem://` deep links using `--middleware-url` instead of `--bhnm-server`

---

## [2.1.0] — 2026-03-26

### Added

- **Per-server push notification routing** — each saved connection stores its own `pushMiddlewareURL` and `webhookSecret`; switching the active server re-registers the APNs device token with the correct middleware and secret automatically
- **Server icon customisation** — saved connections have a choosable SF Symbol icon and accent colour, shown in the server list and detail views
- **Multi-server Settings redesign** — Settings now shows a list of all saved BHNM connections with swipe-to-edit and swipe-to-delete; a dedicated `ServerConfigView` form handles add/edit with an inline icon picker (`IconPickerSheet`)
- **Compact deep link format** — `benem://configure?p=<blob>` packs all fields (including symbol, colour, and push config) into a single AES-256-GCM + zlib payload; legacy `?server=&api_key=` links continue to work
- **`generate_benem_link.py` enhancements** — `--symbol`, `--color`, `--qr` flags; interactive mode (`-i`) with prompts for every field; QR code export via `qrcode` library

---

## [2.0.0] — 2026-03-26

### Added

- **Push notifications** — the app receives real-time push alerts for new incidents via the companion `bhnm-apns` middleware (Docker + Caddy, deployable to any cloud or on-prem server)
- **Middleware authentication** — `/register` and `/webhook` endpoints are protected by `X-Webhook-Token` header or `?secret=` query param; the secret is stored in AppStorage and sent on every registration call
- **APNs entitlement** — `BeNeM.entitlements` includes `aps-environment = development` for device token delivery
- **Notification deep linking** — tapping a push notification navigates directly to the incident; handles both background-tap and cold-launch scenarios
- **Push provisioning via deep link** — `generate_benem_link.py` gains `--push-url` (plain) and `--push-secret` (encrypted) flags; `DeepLinkHandler` parses and applies both on link open

---

## [1.6.0] — 2026-03-26

### Added

- **Push notification foundation** — `AppDelegate` handles APNs token registration and `UNUserNotificationCenterDelegate`; device token is POSTed to `<middleware_url>/register` with `X-Webhook-Token`
- **Push Notifications section in Settings** — middleware URL and webhook secret can be configured per-connection
- **Notification tap handling** — background and foreground taps post `pushNotificationIncidentTapped` via `NotificationCenter`; `ContentView` switches to the Incidents tab and navigates to the tapped incident

---

## [1.5.0] — 2026-03-25

### Added

- **Anomalies column** — an Anomalies (A) row appears below H/S/T in Categories, Sites, and Business Workflows, populated from `anom_threshold_*` fields in the tactical overview API

### Changed

- **Alarm filter** — now hides groups where all H/S/T/A counts are green; informational (blue/acknowledged) hosts no longer prevent a group from being filtered out
- **Value-based navigation** — drill-down links on the Home tab use `NavigationLink(value:)` so tapping the Home tab icon always pops back to the root without losing state
- **Group name column** — centered and word-wraps for long names; empty group names (blank from API) display as "Unknown"; alternating row backgrounds added for readability
- **Labels renamed** — "Tactical Overview" → "Home", "Category" → "Categories", "Site" → "Sites", "Business Workflow" → "Business Workflows"

### Fixed

- **Dashboard H/S/T/A counts** — no longer shows 0 when navigating back before the tactical overview finishes loading

---

## [1.4.2] — 2026-03-25

### Added

- **Version in Splash Screen** — the app version and build number are shown in small, elegant white text at the bottom of the launch screen, fading in and out with the logo
- **Version in Settings** — a new "About" section at the bottom of Settings displays the current app version and build number

### Changed

- **Settings: "Discover BHNM Server"** — the discovery entry in Settings was renamed from "Auto Discovery" to "Discover BHNM Server" for clarity

---

## [1.4.1] — 2026-03-24

### Changed

- **Settings: "Test" button** — the globe icon in the BHNM Server section is replaced by a plain "Test" label for clarity
- **Settings: silent success** — a successful connection test now shows a **green dot** next to the connection name instead of a popup alert; a failed test still shows a red dot and a diagnostic alert; the dot resets when switching or deleting a connection
- **Incident Ticker** — the dashboard ticker now shows only **open (non-acknowledged) incidents**, sorted newest-first; acknowledged incidents are no longer surfaced there
- **Tactical filter** — the alarm filter in Categories / Sites / Business Workflows now keeps only groups with **yellow, orange, or red** host alarms (warning / major / critical); informational (blue) hosts no longer prevent a group from being hidden

### Fixed

- **GroupListView title** — the title (Categories / Sites / Business Workflows) was missing from the navigation bar; the group title is now shown alongside the BMC Helix logo
- **Title centering** — "Active Incidents" and "Devices" navigation titles were visually off-centre because the custom principal toolbar item competed with asymmetric leading/trailing items; both titles now use the standard `.navigationTitle` placement and are always centred
- **Tactical filter reactivity** — `filteredGroups` is now a `@Published` property updated via an explicit `applyFilter()` `didSet` observer, eliminating a SwiftUI rendering edge case where the computed-property approach could fail to trigger a redraw
- **Tactical filter empty state** — when the alarm filter is active but all groups are healthy, the list now shows a "All groups are healthy" message instead of a blank screen
- **App startup without configuration** — removed the legacy Welcome screen; the app now navigates directly to Settings when no server is configured

---

## [1.4.0] — 2026-03-24

### Added

- **Device Detail View** — tap any device in the Devices list to open a full detail screen showing active incidents for that device, performance metric cards (CPU, memory, interfaces, latency, etc.), and network interface details
- **Performance charts on-demand** — each performance metric in Device Detail is a collapsible card that fetches and renders its time-series chart only when expanded, keeping the initial load fast
- **Network interfaces** — Device Detail includes a dedicated Interfaces section listing all polled interfaces with their current state
- **Device list limit** — Settings → Devices now has a stepper (10–100, default 20) to cap how many devices are loaded in the Devices tab
- **Named connections** — multiple BHNM servers can be saved and switched via a connection picker in Settings; the active connection is persisted across launches
- **Delete connection** — saved connections can be removed with a confirmation prompt; deleting the active connection disconnects the service
- **URL scheme import** — `benem://configure` deep links allow a server connection to be imported by URL (e.g. from a QR code or MDM profile); supports `url`, `key`, `pin`, `user`, and `name` parameters
- **SETUP.md + link generator** — `SETUP.md` documents the URL scheme format; a Python script (`scripts/generate_link.py`) and `.env.template` are included for generating import links
- **Secrets infrastructure** — `Secrets.swift` (gitignored) holds optional compile-time defaults; an Xcode build phase emits a warning when the file is absent

### Changed

- **Settings UX** — credentials are now applied immediately on successful test (no separate Save button needed); keyboard dismisses on scroll or tap-outside; the Test Connection button moved inside the BHNM Server section
- **apiService propagation** — switching the active connection now immediately updates all open ViewModels (`IncidentListViewModel`, `DeviceListViewModel`, `TacticalViewModel`) via `onChange` so live data refreshes without requiring navigation

### Fixed

- Test connection now validates against the actual runtime endpoint (`/fw/index.php?r=restful/devices/list`) using the draft credentials, not the previously active ones
- API key and PIN fields are masked (`SecureField`) on the Welcome screen
- Switching server no longer shows stale data from the previous connection; all data arrays are cleared on server change
- `bump_version.sh` rewritten to edit `project.pbxproj` directly (resolves `agvtool` path issues in some Xcode environments)

---

## [1.3.0] — 2026-03-22

### Added

- **S / T alarm columns** — Services and Thresholds badge rows are now visible in the Tactical Overview group rows (currently placeholder zeros; will be populated in a future release when the BHNM API exposes service and threshold incident data)
- **Same-tab navigation reset** — tapping the currently active tab in the custom tab bar pops the navigation stack back to the root of that tab

### Changed

- **App icon** — updated to a new icon set across all required sizes
- **App display name** — renamed to **BeNeM** in `Info.plist`

---

## [1.2.0] — 2026-03-22

### Added

- **Splash screen** — animated logo on launch with shimmer sweep and fade-in/out; auto-dismisses after ~3.6 s; respects `accessibilityReduceMotion`
- **Auto Discovery: connectable filter** — only BHNM Core and Primary instances can be connected to; secondary/probe nodes are shown in the results list but greyed out
- **Auto-refresh on Devices tab** — the auto-refresh countdown ring is now also visible on the Device List screen

### Changed

- **Dashboard data loading optimised** — Category, Site, and Business Workflow summaries now reuse the devices and incidents already fetched by the Dashboard, eliminating a redundant full round-trip to the API on each refresh
- **Form-encoded request bodies** — all POST requests now use `URLQueryItem` / `percentEncodedQuery` for correct percent-encoding of special characters in API keys, passwords, and ACK comments
- **Device identity** — `NetreoDevice.id` is now the device IP address (stable, server-assigned) rather than a random `UUID()`, preventing SwiftUI list flicker during background refresh
- **Alarm colors unified** — `AlarmColor` constants are used consistently across all views; inline `Color(red:green:blue:)` literals removed
- **Debug output guarded** — all `print()` statements and `UserDefaults` debug writes are now inside `#if DEBUG` blocks and are omitted from Release builds
- **Toolbar logo asset separated** — the toolbar logo (`BMCHelixLogo`) and the splash screen logo (`SplashLogo`) now reference independent image assets, so changes to one no longer affect the other

### Removed

- Unused scaffold files deleted: `SimpleNetreoService.swift`, `SimpleContentView.swift`, `DeviceInterfacesView.swift`, `DeviceLatencyView.swift`, `InterfacePerformanceView.swift`, `SimpleDeviceListView.swift`, `SimpleQuickConfigView.swift`
- Unused model types removed: `DevicePerformance`, `APIResponse`, `DeviceListResponse`
- Mock device data and `createMockDevices()` helper removed
- Dead legacy code paths `performLegacyDeviceRequest` and `performModernDeviceRequest` removed

### Fixed

- Auto-retry after network disconnect no longer spawns orphaned tasks; retry is now launched with `Task { }` inside `.task(id:)` to prevent overlapping retries
- `IncidentTickerBanner` no longer uses `AnyView` type erasure; replaced with a direct `@ViewBuilder` conditional
- `URLComponents` force-unwrap (`!`) in incident detail and alarm count requests replaced with safe `guard let`

---

## [1.1.0] — 2026-03-20

### Added

- **Closed incidents** — resolved/closed incidents are now shown alongside active ones in the Incident List, labelled `CLRD`
- **Incident Ticker** — animated news-flash banner on the Dashboard cycles through the latest 3 incidents (right-to-left slide, 4 s dwell); tapping an entry navigates directly to the Incident Detail screen
- **HOSTS / SERVICES / THRESHOLDS summary boxes** — three equal-width cards below the ticker show aggregated alarm badge counts (Green / Blue / Yellow / Orange / Red); zero badges rendered as a grey `0` with a subtle border, matching the Tactical Overview style
- **Auto-retry on disconnect** — all screens automatically retry the connection 15 seconds after a network failure, in addition to the existing manual tap-to-retry
- **BMC Helix logo in toolbar** — the BMC Helix logo appears next to the connection indicator in every screen's navigation bar

### Changed

- **Dashboard title** moved inline into the navigation bar as "Tactical Overview"; the large scrolling header was removed for a cleaner look
- **Custom tab bar** — replaced the native UIKit tab bar with a fully custom SwiftUI implementation; Dashboard, Incidents, and Devices icons are always shown in their brand colors (green / red / blue) regardless of selection state
- **Toolbar button chrome removed** — connection indicator and refresh button no longer render iOS button backgrounds; plain `onTapGesture` is used instead of `Button` wrappers
- **Incidents sorted descending** by Incident ID so the newest incidents always appear at the top
- **Alarm color mapping** updated:
  - `UNREACHABLE` and `MAJOR` states → orange
  - `UP`, `NORMAL`, `RECOVERY`, `CLEARED`, `ALARMS CLEARED` states → green (shown everywhere alarm labels appear)
- **Timestamps** — "just now" replaced with "now" (consistent English throughout)

### Fixed

- Auto-refresh button (`arrow.clockwise`) was invisible in the toolbar because `Group` has no intrinsic size inside a `ToolbarItem`; replaced with `ZStack` + explicit `.frame(width: 26, height: 26)`
- Auto-refresh countdown ring restored with a circular progress overlay around the refresh button

---

## [1.0.0] — 2026-03-19

Initial release.

### Added

#### Core Monitoring
- **Dashboard** — status cards showing active incident count and total monitored device count
- **Tactical Overview** — Category, Site, and Business Workflow tabs with per-group device counts and alarm status badges
- **Incident List** — live list of all active and acknowledged incidents with severity and status badges
- **Incident Detail** — full detail view with primary alarms, related alarms, and incident state log
- **Device counting** — only actively polled devices (`poll=1`) are counted, matching BHNM's own UI behavior

#### Alarm Status
- Alarm color derived from incident detail API (`primary_alarm_log` + `relatedalarms`) rather than parsed severity, giving accurate colors even when the incident list endpoint omits the severity field
- Five-color alarm system: Green (OK) / Blue (Informational) / Yellow (Warning) / Orange (Major) / Red (Critical)
- Badge order left-to-right: Green → Blue → Yellow → Orange → Red, consistent across all screens
- Zero-count badges rendered as plain grey text (no background), non-zero badges use the alarm color

#### Incident Management
- **Swipe to acknowledge** — swipe right on any incident row to ACK
- **Swipe to unacknowledge** — swipe left on any acknowledged incident to UnACK
- Configurable ACK username (Settings → ACK User)

#### Filters
- Filter incidents by severity (Critical / Major / Minor / Warning / Informational)
- Filter incidents by status (Active / Acknowledged / Resolved / Closed)
- Filter tactical groups to show only groups with active (non-green) alarms
- Clear all filters button

#### Auto-refresh
- Automatic data refresh every 120 seconds on all screens
- Visible countdown ring depletes over the interval; tap to refresh immediately
- Pull-to-refresh available on all list views
- Navigation stack preserved during background refresh (no pop-to-root on reload)

#### Settings & Configuration
- Base URL, API Key, PIN (SaaS), and ACK User configuration
- API version selector: Legacy (PHP), API v1, API v2, OpenAPI 3.0
- Configurable request timeout (10–120 s) and retry count (1–10)
- **Connection Test** — validates URL, sends a real HTTP request, and returns a detailed diagnostic message for any error condition
- **Auto Discovery** — scans the local Wi-Fi /24 subnet for BHNM servers via SNMP; discovered servers can be connected to directly from the results list

#### Debug (Settings)
- Debug panel showing raw API field names from the first device and first incident response
- Unmatched incident device names panel (incidents whose device name could not be matched to a known device)

---

[Unreleased]: https://github.com/thomasstolt/BeNeM/compare/v2.6.0...HEAD
[2.6.0]: https://github.com/thomasstolt/BeNeM/compare/v2.5.0...v2.6.0
[2.3.2]: https://github.com/thomasstolt/BeNeM/compare/v2.3.1...v2.3.2
[2.3.1]: https://github.com/thomasstolt/BeNeM/compare/v2.3.0...v2.3.1
[2.3.0]: https://github.com/thomasstolt/BeNeM/compare/v2.2.0...v2.3.0
[2.2.0]: https://github.com/thomasstolt/BeNeM/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/thomasstolt/BeNeM/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/thomasstolt/BeNeM/compare/v1.6.0...v2.0.0
[1.6.0]: https://github.com/thomasstolt/BeNeM/compare/v1.5.0...v1.6.0
[1.5.0]: https://github.com/thomasstolt/BeNeM/compare/v1.4.2...v1.5.0
[1.4.2]: https://github.com/thomasstolt/BeNeM/compare/v1.4.1...v1.4.2
[1.4.1]: https://github.com/thomasstolt/BeNeM/compare/v1.4.0...v1.4.1
[1.4.0]: https://github.com/thomasstolt/BeNeM/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/thomasstolt/BeNeM/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/thomasstolt/BeNeM/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/thomasstolt/BeNeM/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/thomasstolt/BeNeM/releases/tag/v1.0.0
