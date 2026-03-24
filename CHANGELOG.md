# Changelog

All notable changes to BeNeM are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **Note:** BMC Helix Network Management (BHNM) was formerly known as **Netreo**. Internal code identifiers still use the legacy `Netreo` prefix for backwards compatibility.

---

## [Unreleased]

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

[Unreleased]: https://github.com/thomasstolt/BeNeM/compare/v1.4.2...HEAD
[1.4.2]: https://github.com/thomasstolt/BeNeM/compare/v1.4.1...v1.4.2
[1.4.1]: https://github.com/thomasstolt/BeNeM/compare/v1.4.0...v1.4.1
[1.4.0]: https://github.com/thomasstolt/BeNeM/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/thomasstolt/BeNeM/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/thomasstolt/BeNeM/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/thomasstolt/BeNeM/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/thomasstolt/BeNeM/releases/tag/v1.0.0
