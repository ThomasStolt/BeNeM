# Changelog

All notable changes to BeNeM are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **Note:** BMC Helix Network Management (BHNM) was formerly known as **Netreo**. Internal code identifiers still use the legacy `Netreo` prefix for backwards compatibility.

---

## [Unreleased]

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

[Unreleased]: https://github.com/thomasstolt/BeNeM/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/thomasstolt/BeNeM/releases/tag/v1.0.0
