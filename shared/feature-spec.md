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
- v0.1.1 (planned): swipe ACK / UnACK, real incident detail screen, Settings screen
- No native-style swipe gesture library — touch-based pull-to-refresh is hand-rolled in `components/PullToRefresh.tsx`
