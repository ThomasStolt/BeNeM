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
