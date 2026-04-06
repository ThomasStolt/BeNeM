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
**Status:** shipped-ios, in-progress-pwa
**API:** `POST /api/incident_api.php` (method=getincidents)

#### Behaviour (both platforms)
- Display open incidents
- Swipe gestures for acknowledge / unacknowledge
- Pull-to-refresh and 120-second auto-refresh
- Navigate to incident detail on tap
- Badge with alarm state counts from `getincidentdetail` (`primary_alarm_log` + `relatedalarms`)

#### iOS-specific
- SwiftUI `List` with native swipe actions (right = ACK, left = UnACK)
- Auto-refresh countdown ring in the toolbar (`AutoRefreshButton`)

#### PWA-specific
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

### Feature: Navigation (Tab Bar)
**Status:** shipped-ios, shipped-pwa

#### Behaviour (both platforms)
- Bottom tab bar with Dashboard, Incidents, Devices tabs
- Persistent across screens (except Settings)
- Active tab highlighting

#### iOS-specific
- Native UITabBarController / SwiftUI TabView

#### PWA-specific
- v0.3.0: React Router NavLink-based tab bar, fixed bottom position

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
