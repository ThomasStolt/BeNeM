# BeNeM — Be Netreo Mobile

A native iOS app for [Netreo](https://www.netreo.com) network monitoring systems. Monitor your infrastructure, manage incidents and acknowledge alerts directly from your iPhone.

## Features

- **Incident List** — live view of all active incidents with color-coded alarm counts (red / orange / yellow / green / blue)
- **Acknowledge / Unacknowledge** — swipe right to ACK, swipe left to Unack, with instant local status update (no full-page reload)
- **Incident Detail** — primary alarms, related alarms, and the full incident state log
- **Filters** — filter incidents by severity and status
- **Pull-to-refresh** — manual refresh at any time
- **Connection Test** — built-in connectivity test with detailed diagnostics directly in Settings
- **Multiple API versions** — supports Legacy (PHP), API v1, API v2 and OpenAPI 3.0 endpoints

## Requirements

- iOS 16.0 or later
- Xcode 15 or later
- A running Netreo instance (on-premise or SaaS)

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

> **Note:** For corporate or self-signed certificate servers the app includes `NSAllowsArbitraryLoads` in its `Info.plist`. Review and adjust your ATS settings before submitting to the App Store.

## Configuration

On first launch, open the **Settings** tab and enter:

| Field | Description |
|---|---|
| Base URL | Your Netreo server URL, e.g. `https://netreo.example.com` |
| API Key | Your Netreo API key |
| PIN | Only required for SaaS deployments |
| ACK User | Username recorded when acknowledging incidents (defaults to `mobile`) |
| API Version | Choose the version that matches your Netreo deployment |
| Timeout | Request timeout in seconds (default: 30s) |
| Retry Count | Number of retries on failure (default: 3) |

Use the **Test Connection** button to verify your settings before using the app.

## Project Structure

```
BeNeM/
├── Models/
│   ├── NetreoIncident.swift       # Incident data model
│   ├── IncidentDetail.swift       # Incident detail / alarm log model
│   └── NetreoDevice.swift         # Device data model
├── Services/
│   ├── NetreoAPIService.swift     # All API calls (incidents, ACK, detail)
│   └── NetreoAPIConfiguration.swift  # URL building, endpoint routing
├── ViewModels/
│   └── IncidentListViewModel.swift   # Filtering, alarm count loading
├── Views/
│   ├── IncidentListView.swift     # Incident list + swipe actions
│   ├── IncidentDetailView.swift   # Incident detail screen
│   └── SettingsView.swift         # Configuration + connection test
└── BeNeMApp.swift                 # App entry point
```

## API Compatibility

The app primarily uses Netreo's legacy PHP endpoints for incident management:

| Action | Endpoint |
|---|---|
| List incidents | `POST /api/incident_api.php?method=getincidents` |
| Incident detail | `GET /api/incident_api.php?method=getincidentdetail` |
| Acknowledge | `GET /utils/incident_ack.php` |
| Unacknowledge | `POST /fw/index.php?r=restful/incident/unacknowledge` |

## License

MIT — see [LICENSE](LICENSE) for details.
