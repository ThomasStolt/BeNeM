# BeNeM — BMC Helix Network Management Mobile Client

A native iOS app for **BMC Helix Network Management** (BHNM). Monitor your infrastructure, manage incidents, and acknowledge alerts directly from your iPhone.

> **Note:** BMC Helix Network Management (BHNM) was formerly known as **Netreo**. Internal code identifiers (class names, AppStorage keys) still use the legacy `Netreo` prefix for backwards compatibility and will be migrated in a future release.

## Features

- **Dashboard** — at-a-glance summary with active incident count, total device count, an animated incident ticker, and HOSTS / SERVICES / THRESHOLDS alarm summaries
- **Tactical Overview** — Category / Site / Business Workflow lists showing each group's device count and color-coded alarm status (Green / Blue / Yellow / Orange / Red)
- **Incident List** — live view of active, acknowledged, and closed incidents with severity badges and per-incident alarm counts; sorted newest-first by Incident ID
- **Acknowledge / Unacknowledge** — swipe right to ACK, swipe left to UnACK, with instant local status update
- **Incident Detail** — primary alarms, related alarms, and the full incident state log
- **Incident Ticker** — animated news-flash banner on the Dashboard cycles through the latest 3 incidents; tap to navigate directly to the detail screen
- **Filters** — filter incidents by severity and status; filter tactical groups to show only those with active alarms
- **Auto-refresh** — data refreshes automatically every 120 seconds with a visible countdown ring; tap the ring to refresh immediately
- **Auto-retry** — all screens automatically retry the connection 15 seconds after a network failure
- **Pull-to-refresh** — manual refresh at any time by pulling down any list
- **Auto Discovery** — scans your local Wi-Fi subnet for BHNM servers (Settings → Auto Discovery)
- **Connection Test** — built-in connectivity test with detailed diagnostics
- **Multiple API versions** — supports Legacy (PHP), API v1, API v2, and OpenAPI 3.0 endpoints

## Requirements

- iOS 16.0 or later
- Xcode 15 or later
- A running BHNM instance (on-premise or SaaS)

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/thomasstolt/BeNeM.git
cd BeNeM
```

### 2. Open in Xcode

```bash
open BeNeM.xcodeproj
```

### 3. Configure signing

1. Select the `BeNeM` target in Xcode
2. Under **Signing & Capabilities**, select your Apple Developer Team
3. Adjust the Bundle Identifier if needed (default: `com.tstolt.benem`)

### 4. Build & Run

- **Simulator**: Select any iPhone simulator and press ▶
- **Physical device**: Connect your iPhone, select it as the destination and press ▶

Alternatively, use the included build script:

```bash
# Copy the example config and fill in your device UDID
cp build.local.sh.example build.local.sh
# Edit build.local.sh — set BENEM_DEVICE_ID to your device's UDID

# Build and deploy
./build_and_deploy.sh
```

> **Note:** For corporate or self-signed certificate servers the app includes `NSAllowsArbitraryLoads` in its `Info.plist`. Review and adjust your ATS settings before submitting to the App Store.

## Configuration

On first launch, open the **Settings** tab and enter:

| Field | Description |
|---|---|
| Base URL | Your BHNM server URL, e.g. `https://bhnm.example.com` |
| API Key | Your BHNM API key |
| PIN | Only required for SaaS deployments |
| ACK User | Username recorded when acknowledging incidents (defaults to `mobile`) |
| API Version | Choose the version that matches your BHNM deployment |
| Timeout | Request timeout in seconds (default: 30 s) |
| Retry Count | Number of retries on failure (default: 3) |

Use the **Test Connection** button to verify your settings before using the app.

### Auto Discovery

If you are on the same Wi-Fi network as your BHNM server, tap **Settings → Auto Discovery** to automatically scan the local /24 subnet for BHNM instances. Discovered servers can be connected to directly from the results list.

## Project Structure

```
BeNeM/
├── Models/
│   ├── NetreoIncident.swift          # Incident data model
│   ├── IncidentDetail.swift          # Incident detail / alarm log model
│   ├── NetreoDevice.swift            # Device data model
│   └── GroupSummary.swift            # Aggregated alarm status per group
├── Services/
│   ├── NetreoAPIService.swift        # All API calls (incidents, devices, tactical, ACK)
│   ├── NetreoAPIConfiguration.swift  # URL building, endpoint routing
│   └── NetworkDiscovery.swift        # Local Wi-Fi subnet scan for BHNM servers
├── ViewModels/
│   ├── IncidentListViewModel.swift   # Filtering, sorting, alarm count loading
│   ├── DeviceListViewModel.swift     # Device list loading
│   └── TacticalViewModel.swift       # Category / Site / Business Workflow loading
├── Views/
│   ├── DashboardView.swift           # Home: status cards, incident ticker, alarm summaries
│   ├── GroupListView.swift           # Group list with alarm badges and device count
│   ├── IncidentListView.swift        # Incident list + swipe ACK/UnACK
│   ├── IncidentDetailView.swift      # Incident detail screen
│   ├── AutoDiscoveryView.swift       # Wi-Fi server discovery UI
│   ├── AutoRefreshButton.swift       # Countdown ring + refresh button + connection badge
│   └── SettingsView.swift            # Configuration + connection test + debug info
└── BeNeMApp.swift                    # App entry point
```

> **Note on class names:** Swift types use the legacy `Netreo` prefix (e.g. `NetreoAPIService`, `NetreoIncident`) as they predate the product rebrand. AppStorage keys (`netreo_base_url`, `netreo_api_key`, etc.) are also kept unchanged to preserve existing user settings.

## API Compatibility

The app uses a mix of BHNM's legacy PHP endpoints and RESTful endpoints:

| Action | Method | Endpoint |
|---|---|---|
| List incidents | POST | `/api/incident_api.php` (`method=getincidents`) |
| Incident detail | GET | `/api/incident_api.php` (`method=getincidentdetail`) |
| Acknowledge | POST | `/fw/index.php?r=restful/incident/acknowledge` |
| Unacknowledge | POST | `/fw/index.php?r=restful/incident/unacknowledge` |
| List devices | POST | `/fw/index.php?r=restful/devices/list` |
| List categories | POST | `/fw/index.php?r=restful/category/list` |
| List sites | POST | `/fw/index.php?r=restful/site/list` |
| List strategic groups | POST | `/fw/index.php?r=restful/strategic-group/list` |
| Strategic group members | POST | `/fw/index.php?r=restful/strategic-group/device-list` |

> **Note on alarm status:** The BHNM device list API does not expose a real-time alarm color or health state. BeNeM derives each device's current status from active incidents (matched by device name) using the incident detail API for accurate alarm colors, then aggregates them per group. Only actively monitored devices (`poll=1`) are counted, matching BHNM's own UI behavior.

## Versioning

Releases follow [Semantic Versioning](https://semver.org): `MAJOR.MINOR.PATCH`.

```bash
# Bump version and build number (runs xcrun agvtool internally)
./scripts/bump_version.sh patch   # 1.1.0 → 1.1.1
./scripts/bump_version.sh minor   # 1.1.0 → 1.2.0
./scripts/bump_version.sh major   # 1.1.0 → 2.0.0
```

See [CHANGELOG.md](CHANGELOG.md) for the full release history.

## License

MIT — see [LICENSE](LICENSE) for details.
