# BeNeM – Claude Code Context

BeNeM (Be Netreo Mobile) is an iOS app built with Swift/SwiftUI for monitoring network devices and incidents via the **BMC Helix Network Management** (BHNM) API.

> **Naming note:** BHNM was formerly known as **Netreo**. Swift type names (`NetreoAPIService`, `NetreoIncident`, `NetreoDevice`, `NetreoAPIConfiguration`) and AppStorage keys (`netreo_base_url`, `netreo_api_key`, etc.) still use the legacy prefix for backwards compatibility and should not be renamed without a coordinated migration.

## Project Structure

```
BeNeM/
├── Services/
│   ├── NetreoAPIService.swift       # All API calls (incidents, devices, tactical, ACK/UnACK)
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
│   └── TacticalViewModel.swift      # Loads GroupSummary for Category/Site/Business Workflow
└── Views/
    ├── IncidentListView.swift        # Swipe gestures: right = ACK, left = UnACK
    ├── IncidentDetailView.swift
    ├── DashboardView.swift           # Home: StatusCards + Tactical Overview
    ├── GroupListView.swift           # Lists groups with alarm badges and device count
    ├── AutoRefreshButton.swift       # Reusable countdown ring + refresh button (120 s)
    ├── AutoDiscoveryView.swift       # Wi-Fi server discovery UI
    └── SettingsView.swift
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
| Device list | POST | `/fw/index.php?r=restful/devices/list` |
| Category names | POST | `/fw/index.php?r=restful/category/list` |
| Site names | POST | `/fw/index.php?r=restful/site/list` |
| Strategic groups | POST | `/fw/index.php?r=restful/strategic-group/list` |
| Strategic group devices | POST | `/fw/index.php?r=restful/strategic-group/device-list` (body: `id=<groupID>`) |

### ACK / UnACK Body (form-urlencoded)
```
password=<apiKey>
incident_id=<id>
user=<username>
comment=<text>
pin=<pin>          # optional
unacknowledge=1    # only for UnACK
```

## Tactical Overview (Dashboard → Category / Site / Business Workflow)

`GroupListView` displays per group:
- **DEVICES** (outlined blue badge, leftmost): total actively-polled devices (`poll=1` only — matches BHNM UI)
- **H / S / T** alarm badge rows: Hosts / Services / Thresholds (S + T are placeholder zeros for now)
- Badge colors (left → right): Green / Blue / Yellow / Orange / Red
- Badges with value 0 are shown as grey text with no background
- Filter button (funnel icon) in the toolbar hides all-green groups

### Alarm Status Derivation
The BHNM device API (`restful/devices/list`) returns **no real-time alarm state**. Status is derived from **incidents** instead:
1. Fetch devices (for Site/Category assignment via `site`/`category` fields)
2. Fetch active incidents
3. Match: `incident.deviceName` ↔ `device.name` (case-insensitive, base-hostname fallback)
4. For each matched incident, call `getincidentdetail` to read `primary_alarm_log` + `relatedalarms`
5. Derive worst `AlarmColor` from actual alarm entries (not parsed severity, which is unreliable)
6. Aggregate by Site / Category / Business Workflow

Business Workflows additionally use `restful/strategic-group/device-list` to map IPs to groups.

## Data Refresh

Data refreshes **automatically every 120 seconds** via `AutoRefreshButton` (a Timer.publish-based countdown ring visible in every toolbar). Users can also:
- Tap the ring to refresh immediately
- Pull-to-refresh on any list view

**Navigation is preserved during refresh** — the loading spinner only shows on the initial load (when the data arrays are empty). Background refreshes update data in place without collapsing the navigation stack.

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

- `NetreoAPIService` still has legacy code paths (`configuration.version == .legacy`). Incidents and ACK/UnACK use the RESTful endpoints directly (no `version` switch).
- The device API returns **no alarm color field** — real-time status is derived from the incident detail API (`getincidentdetail`) using `primary_alarm_log` + `relatedalarms` alarm entries.
- Severity fields are often missing from the BHNM incident list API; the alarm color from the detail API is authoritative.
- SourceKit regularly reports false-positive errors in this project (e.g. "Cannot find type X in scope"). `xcodebuild` succeeds regardless — trust the compiler, not SourceKit.
- Debug info is temporarily stored in `UserDefaults`:
  - `debug_incident_fields`: fields from the first incident
  - `debug_device_fields`: fields from the first device
  - `debug_unmatched_incidents`: incident device names that couldn't be matched to a device
  - All are visible in **Settings → Debug** and can be refreshed with the "Refresh" button.
