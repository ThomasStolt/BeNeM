# BeNeM iOS – Claude Code Context

BeNeM (Be Netreo Mobile) is an iOS app built with Swift/SwiftUI for monitoring network devices and incidents via the **BMC Helix Network Management** (BHNM) API.

> Part of the BeNeM monorepo. See `../CLAUDE.md` for cross-cutting rules, `../middleware/CLAUDE.md` for the push middleware, and `../shared/` for API contracts and feature specs.

> **Naming note:** BHNM was formerly known as **Netreo**. Swift type names (`NetreoAPIService`, `NetreoIncident`, `NetreoDevice`, `NetreoAPIConfiguration`) and AppStorage keys (`netreo_base_url`, `netreo_api_key`, etc.) still use the legacy prefix for backwards compatibility and should not be renamed without a coordinated migration.

## Project Structure

```
BeNeM/
├── Services/
│   ├── NetreoAPIService.swift       # All API calls (incidents, devices, tactical, ACK/UnACK, performance)
│   ├── NetreoAPIConfiguration.swift # URL configuration, endpoints, HTTP methods
│   └── NetworkDiscovery.swift       # Local Wi-Fi /24 subnet scan for BHNM servers (SNMP)
├── Models/
│   ├── NetreoIncident.swift
│   ├── NetreoDevice.swift
│   ├── IncidentDetail.swift
│   └── GroupSummary.swift           # Aggregated alarm status per group (Site/Category/BW)
├── ViewModels/
│   ├── IncidentListViewModel.swift
│   ├── DeviceListViewModel.swift
│   ├── DeviceDetailViewModel.swift  # Concurrent incident + performance loading for one device
│   └── TacticalViewModel.swift      # Loads GroupSummary for Category/Site/Business Workflow
├── Services/
│   └── DeepLinkHandler.swift        # Parses + applies benem:// config URLs (AES-GCM decryption)
└── Views/
    ├── SplashView.swift              # Animated launch screen with logo shimmer + version
    ├── DashboardView.swift           # Home: StatusCards + Drill Down links + Incident Ticker + H/S/T/A summary cards
    ├── IncidentListView.swift        # Swipe gestures: right = ACK, left = UnACK
    ├── IncidentDetailView.swift
    ├── DeviceDetailView.swift        # Device detail: incidents, performance charts, interfaces
    ├── GroupListView.swift           # Lists groups with alarm badges and device count
    ├── AutoRefreshButton.swift       # Reusable countdown ring + refresh button (120 s)
    ├── AutoDiscoveryView.swift       # Wi-Fi server discovery UI
    ├── SettingsView.swift
    ├── ServerConfigView.swift        # Add/edit server: connection fields, push config, test & save
    ├── FloppyDiskIcon.swift          # Custom floppy disk icon drawn as SwiftUI Canvas
    ├── QRScannerView.swift           # Full-screen camera QR scanner for benem:// URLs
    ├── BeNeMApp.swift                # App entry point + URL scheme handler
    └── AppDelegate.swift             # APNs registration, UNUserNotificationCenterDelegate, deep-link tap handler
```

## API – BHNM

The app communicates with a self-hosted BHNM instance.

### Authentication
- `password`: API key (stored in `NetreoAPIConfiguration.apiKey`)
- `pin`: Optional PIN (stored in `NetreoAPIConfiguration.pin`)

### Used Endpoints

| Function | Method | URL |
|---|---|---|
| Fetch incidents | POST | `/api/incident_api.php` (method=getincidents) |
| Acknowledge incident | POST | `/fw/index.php?r=restful/incident/acknowledge` |
| Unacknowledge incident | POST | `/fw/index.php?r=restful/incident/unacknowledge` |
| Incident detail | GET | `/api/incident_api.php` (method=getincidentdetail) |
| Device list (paginated) | POST | `/fw/index.php?r=restful/devices/list` (body: `recordStart=<n>&recordCount=<n>`) → returns `{totalRecords, displayRecords, devices:[]}` |
| Device search | POST | `/fw/index.php?r=restful/devices/find` (body: `name=<query>`) → substring match, returns array |
| Category devices | POST | `/fw/index.php?r=restful/category/device-list` (body: `id=<categoryId>`) |
| Site devices | POST | `/fw/index.php?r=restful/site/device-list` (body: `id=<siteId>`) |
| Tactical overview (H/S/T) | POST | `/fw/index.php?r=restful/tactical-overview/data` (body: `grouping_type=category\|site\|app`) |
| Find device by name | POST | `/fw/index.php?r=restful/devices/find` (body: `name=<deviceName>`) → returns `dev_index` |
| Performance categories | POST | `/fw/index.php?r=restful/devices/performance-category` (body: `device_id=<id>`) |
| Performance instances | POST | `/fw/index.php?r=restful/devices/performance-instance-per-category` (body: `device_id=<id>&id=<categoryId>`) |
| Time-series metrics | POST | `/fw/index.php?r=restful/devices/timeseries-metrics` (see body parameters below) |
| Time-series metrics (batch) | POST | `/fw/index.php?r=restful/devices/timeseries-metrics` (same endpoint, single call returns multiple metrics) |

### Time-Series Metrics Body (multipart/form-data)
```
password=<apiKey>
groupFilterBy=device
groupFilterValue=<deviceName>
metricFilterStatGroup=<statGroup>   # e.g. "CPU", "Memory", "Disks", interface category name
metricFilterUnits=<units>           # e.g. "%", "Volt", "Processes", "System Load"
timeFrameFilterBy=time_offset
timeFrameFilterValue=<timeFrame>    # "Last Hour", "Last 2 Hours", "Last 5 Hours", or "Last 24 Hours"
returnFormatFilterBy=average
pin=<pin>                           # optional
```
Response: `{ "metrics": [ { "timeStamp": "<epoch>", "value1": <num>, "value2": <num>, "instanceDescr": <str>, ... } ] }`

**Empty-unit metrics:** When a metric has no unit from discovery (`unit: ""`), use the metric title as `metricFilterUnits` — except where the API expects a different value (e.g. "Running Processes" → `metricFilterUnits=Processes`). The correct unit can be found in the `instanceDescr` parenthetical: `"Running Processes for device (Processes)"`.

**Batch fetching:** A single API call with the same `statGroup`+`units` returns ALL matching metrics (e.g. `CPU`+`%` returns CPU Utilization AND all CPU Cores). Use `instanceDescr` or `metricId` to distinguish them. The app uses `fetchTimeSeriesBatch()` for CPU Cores to fetch once and split by `instanceDescr`.

Interface instances produce two `PerformanceInstance` entries per physical interface (suffixed `-in`/`-out`); `valueKey` selects `value1` (inbound) or `value2` (outbound) from the response.

### ACK / UnACK Body (form-urlencoded)
```
password=<apiKey>
incident_id=<id>
user=<username>
comment=<text>
pin=<pin>          # optional
unacknowledge=1    # only for UnACK
```

## Tactical Overview (Home → Categories / Sites / Business Workflows)

Navigation from Home uses value-based `NavigationLink(value:)` with a `TacticalDestination` enum and `.navigationDestination(for:)`, so tapping the Home tab always pops back to the root regardless of depth.

`GroupListView` displays per group:
- **DEVICES** (outlined blue badge, leftmost): total of all host-status counts from the tactical overview endpoint
- **H / S / T / A** alarm badge rows: Hosts / Services / Thresholds / Anomalies
- Badge colors (left → right): Green / Blue / Yellow / Orange / Red
- Badges with value 0 are shown as grey text with no background
- Group name column is centered and word-wraps for long names
- Alternating row backgrounds (every second row has a very light gray tint)
- Empty group names (blank from API) are displayed as "Unknown"
- Filter button (funnel icon) in the toolbar hides groups where all H/S/T/A values are green (`hasAlarms` computed property on `GroupSummary`)

### Alarm Status Derivation
H/S/T/A counts come directly from `restful/tactical-overview/data` — a single POST request per view that returns pre-aggregated, real-time status counts from BHNM's monitoring core (the same source as the BHNM web dashboard). No device or incident fetching is needed for the tactical views.

Anomalies use the `anom_threshold_*` prefix in the API response.

`grouping_type` mapping in `TacticalViewModel.GroupType`:
- `.category` → `"category"`
- `.site` → `"site"`
- `.businessWorkflow` → `"app"`

Status field → badge color mapping:
- `*_ok_count` → Green
- `*_ack_count` → Blue
- `*_warn_count` → Yellow
- `*_un_count` → Orange (unknown)
- `*_crit_count` → Red

## Data Refresh

Data refreshes **automatically every 120 seconds** via `AutoRefreshButton` (a Timer.publish-based countdown ring visible in every toolbar). Users can also:
- Tap the ring to refresh immediately
- Pull-to-refresh on any list view

**Navigation is preserved during refresh** — the loading spinner only shows on the initial load (when the data arrays are empty). Background refreshes update data in place without collapsing the navigation stack.

## Push Notifications (iOS consumer side)

The iOS app receives push notifications via the `bhnm-apns` middleware.
See `../middleware/CLAUDE.md` for middleware-side details (deployment,
auth, APNs routing) and `../CLAUDE.md` for the cross-cutting architecture.

### AppStorage keys (iOS-side config)
- `push_middleware_url` — middleware base URL, configurable in Settings → Push Notifications
- `push_middleware_secret` — shared secret for authenticating requests to the middleware (sent as `X-Webhook-Token` header on `/register`)

### iOS Side
- `AppDelegate` (`AppDelegate.swift`) handles APNs token registration and `UNUserNotificationCenterDelegate`
- On app start, the device token is POSTed to `<middleware_url>/register` with `X-Webhook-Token` header
- Notification taps post `Notification.Name.pushNotificationIncidentTapped` via `NotificationCenter`
- `ContentView` listens and switches to the Incidents tab, passing the `incident_id` to `IncidentListView`
- `IncidentListView` loads incidents if needed and navigates directly to `IncidentDetailView`
- Cold-launch (app killed): `AppDelegate.shared.pendingIncidentID` is read in `ContentView.onAppear`
- `BeNeM.entitlements` contains `aps-environment = development` (required for APNs token delivery)

### Notification Payload (APNs custom data)
```json
{ "aps": { "alert": {...}, "sound": "default" }, "incident_id": "<id>" }
```

### Deep Link — Push Notification Config
`generate_benem_link.py` supports provisioning push settings via the `benem://` URL scheme:
```bash
python3 generate_benem_link.py \
  --bhnm-server https://bhnm.example.com \
  --api_key YOUR_API_KEY \
  --push_url https://bhnm-apns.hurrikap.org \   # plain text
  --push_secret YOUR_WEBHOOK_SECRET              # encrypted
```
- `push_url` is included plain text in the link
- `push_secret` is AES-256-GCM encrypted (same key as `api_key`)
- `DeepLinkHandler.swift` decrypts and applies both on link open

## Versioning

Schema: `MAJOR.MINOR.PATCH` (SemVer) + build number

| Variable | Meaning | Example |
|---|---|---|
| `MARKETING_VERSION` | User-visible version (App Store) | `1.0.0` |
| `CURRENT_PROJECT_VERSION` | Build number (monotonically increasing) | `1` |

```bash
# Patch release (bugfix): 1.0.0 → 1.0.1, build +1
./scripts/bump_version.sh patch

# Minor release (new feature): 1.0.0 → 1.1.0, build +1
./scripts/bump_version.sh minor

# Major release (breaking): 1.0.0 → 2.0.0, build +1
./scripts/bump_version.sh major
```

The script uses `xcrun agvtool` and writes directly to `project.pbxproj`.

## Build & Deploy

```bash
# Copy the example config and fill in your device UDID
cp build.local.sh.example build.local.sh
# edit build.local.sh — set BENEM_DEVICE_ID to your device's UDID

# Build and deploy (device if configured, simulator otherwise)
./build_and_deploy.sh
```

Your device UDID can be found in Xcode → Window → Devices and Simulators, or via:
```bash
xcrun devicectl list devices
```

## Important Notes

- **Minimum BHNM version:** 26.1.02. The app uses UID-based device identity, pagination, model/serial fields, and interface details — all require 26.1.01+.
- **Device identity** uses `UID` (root_id from BHNM) as the primary identifier, not IP. The `GUID` field provides globally unique cross-deployment identification.
- `NetreoAPIService` still has legacy code paths (`configuration.version == .legacy`). Incidents and ACK/UnACK use the RESTful endpoints directly (no `version` switch).
- **Incident loading** uses the middleware's cached endpoint (`GET /api/v1/incidents`) which returns incidents enriched with `alarm_counts` and `alert_type` in a single response. `fetchCachedIncidents()` in `NetreoAPIService` calls this endpoint; if it fails (middleware down, cache cold), it falls back to the legacy `getincidents` + per-incident `getincidentdetail` flow. The `alarm_counts` field in the JSON response uses `[String: Any]` (not `[String: Int]`) due to JSONSerialization producing NSNumber values.
- The device list API returns **no alarm color field**. For `IncidentDetailView`, `getincidentdetail` is still called for full detail.
- The **Tactical Overview** (H/S/T aggregates) no longer uses incident or device data — it calls `restful/tactical-overview/data` directly.
- SourceKit regularly reports false-positive errors in this project (e.g. "Cannot find type X in scope"). `xcodebuild` succeeds regardless — trust the compiler, not SourceKit.
- Debug info is temporarily stored in `UserDefaults`:
  - `debug_incident_fields`: fields from the first incident
  - `debug_device_fields`: fields from the first device
  - All are visible in **Settings → Debug** and can be refreshed with the "Refresh" button.
