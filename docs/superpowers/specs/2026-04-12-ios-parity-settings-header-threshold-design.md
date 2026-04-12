# iOS Parity: Settings UX, AppHeader, Middleware Enforcement & Threshold Cache

**Date:** 2026-04-12  
**Platforms:** iOS only  
**Status:** Approved for implementation

## Overview

Four related improvements to bring the iOS app to parity with the PWA and enforce the middleware-always architecture rule:

1. **Middleware enforcement** — remove the direct-BHNM fallback path; middleware URL is now required
2. **Settings server list UX** — radio select button, inline delete with confirmation, QR import without auto-switch
3. **AppHeader parity** — active server name subtitle in all four tab toolbars; M:SS countdown in `AutoRefreshButton`; Settings gets a connection badge
4. **Threshold Cache / HEALTHY count** — `GET /api/v1/threshold-counts` integration, per-device service check count, alarm badges on device list rows

---

## 1. Middleware Enforcement

### Motivation

The PWA always routes API calls through the middleware (`config.baseUrl`), sending `X-BHNM-Target` as a header. iOS has an explicit fallback that bypasses the middleware when `baseURL` (middleware URL) is empty:

```swift
// ContentView.swift — to be removed
let serviceBaseURL = baseURL.isEmpty ? bhnmURL : baseURL
```

Direct-to-BHNM connections are never valid in production. The middleware is mandatory.

### Changes

**`ContentView.updateAPIService()`**
- Guard on `!baseURL.isEmpty && !apiKey.isEmpty` (was `!bhnmURL.isEmpty && !apiKey.isEmpty`)
- Remove the ternary fallback; always use `baseURL` as `serviceBaseURL`
- `bhnmURL` is still passed as `configuration.bhnmURL` (forwarded by `NetreoAPIService` as `X-BHNM-Target`)
- Remove the comment "connect directly to BHNM otherwise"

**`ContentView.mainTabs`**
- Change guard from `!bhnmURL.isEmpty && !apiKey.isEmpty` → `!baseURL.isEmpty && !apiKey.isEmpty`

**`ServerConfigView`**
- Remove the `if mwURLString.isEmpty { testBase = bhnmURLString }` branch in the test-connection logic
- The test always hits `mwURLString + /ha_status` with `X-BHNM-Target: bhnmURLString`
- Both BHNM URL and Middleware URL are required for save. `saveConnection()` already validates `bhnmURL`; add an equivalent guard for `mwURLString.isEmpty` that shows the same "Could not parse..." alert style before the connection test fires
- The migration banner in `SettingsView` (shown when `bhnmURL` is empty on an existing connection) is unchanged

---

## 2. Settings Server List UX

### 2a. Radio Select Button

Replace the passive green-dot indicator with an interactive circle button.

**Visual:**
- 22×22 circle button, leftmost in each server row
- Active state: sky-blue fill (`Color.accentColor`) with a white SF Symbol checkmark (`checkmark`, weight `.bold`, size 10pt)
- Inactive state: empty circle with `Color(.systemGray4)` stroke

**Behaviour:**
- Tapping the circle on an **inactive** server → opens the existing `SwitchServerPopup` confirmation dialog
- Tapping the circle on the **active** server → navigates to edit (same as the current `NavigationLink` on active rows)
- The server name/host text area → always navigates to edit for both active and inactive rows (the `chevron.right` button on inactive rows is removed; the circle handles selection, the text area handles editing)

### 2b. Inline Delete

Add a trash icon button to each row, trailing of the server info.

**Visual:**
- `Image(systemName: "trash")` in `Color(.systemGray3)` by default
- Confirmation state: label changes to `"Delete?"` in `.red`; icon remains

**Behaviour:**
- First tap → row enters confirmation state (icon + label turn red, label reads "Delete?")
- Second tap on the same row's button → deletes the server, reloads the list
- Tapping anywhere else (another row, outside the list) → resets confirmation state
- **Active server protection:** attempting to delete the active server shows an alert: "Switch to another server before deleting the active one." Deletion is blocked until a different server is active.
- Only one row can be in confirmation state at a time; selecting a different row's trash resets the previous one

**State:** `@State private var deleteConfirmID: UUID? = nil` in `SettingsView`

### 2c. QR Import — No Auto-Switch

**`DeepLinkHandler.applyPendingImport()`**
- Remove: `ud.set(upsertedID.uuidString, forKey: "netreo_active_connection_id")`
- The imported server is saved/upserted in the connections list but does not become the active server
- No other UX change; the confirmation sheet text remains as-is
- Push re-registration block (currently gated on `imp.notificationsEnabled`) is also removed from `applyPendingImport()` since the server is not being activated

---

## 3. AppHeader Parity

### 3a. Active Server Name Storage

Add a new AppStorage key `"netreo_active_connection_name"` (String, default `""`).

Written in:
- `SettingsView.activateConnection(_:)` — write `new.name`
- `ContentView.updateAPIService()` — read the active connection's name from `loadSavedConnections()` and write it (keeps in sync after app restart)

All four tab views declare `@AppStorage("netreo_active_connection_name") private var activeServerName = ""` and use it in the toolbar.

### 3b. Principal Toolbar Item (All Four Tabs)

Replace the current `HStack { logo + title }` with:

```swift
VStack(spacing: 1) {
    HStack(spacing: 6) {
        Image("BMCHelixLogo")
            .resizable().scaledToFit()
            .frame(width: 22, height: 22)
        Text(title)
            .font(.system(size: 17, weight: .bold))
    }
    if !activeServerName.isEmpty {
        Text(activeServerName)
            .font(.caption2)
            .foregroundColor(.secondary)
    }
}
```

Applied to: `DashboardView`, `IncidentListView`, `DeviceListView`, `SettingsView`.

### 3c. Settings Toolbar Additions

`SettingsView` currently has no `ConnectionBadgeButton` and no `AutoRefreshButton`. Add:

- **Leading:** `ConnectionBadgeButton` with derived status:
  - `.connected` when `baseURL` and `apiKey` are both non-empty
  - `.disconnected` otherwise
  - No `.checking` state (Settings makes no live API calls); tapping it does nothing (no-op `onRetry`)
- **Trailing:** none — Settings has no auto-refresh (same as PWA)

### 3d. AutoRefreshButton — M:SS Countdown Text

Increase frame from 26×26 to 32×32. Replace the `Image(systemName: "arrow.clockwise")` with countdown text when not loading.

```swift
// Not loading — text replaces icon
let remaining = max(0, interval - elapsed)
let minutes = Int(remaining) / 60
let seconds = Int(remaining) % 60
let label = "\(minutes):\(String(format: "%02d", seconds))"

Text(label)
    .font(.system(size: 9, weight: .bold, design: .monospaced))
    .foregroundColor(Color(.systemGray3))
```

The ring (`Circle().trim(from:to:)`) remains unchanged. Loading state (`ProgressView`) unchanged.

---

## 4. Threshold Cache / HEALTHY Count

### 4a. New API Methods in `NetreoAPIService`

**`fetchThresholdCounts() async throws -> [String: Int]`**
- `GET /api/v1/threshold-counts`
- Headers: `X-Proxy-Token: proxyToken`, `X-BHNM-Target: bhnmURL`
- Response: JSON object `{ "deviceName": Int, ... }` — parse with `JSONDecoder` (or `JSONSerialization` for `[String: Any]` → `[String: Int]`)
- Called once at app-level refresh; stale after 10 minutes

**`fetchDeviceServices(deviceName: String) async throws -> Int`**
- Uses existing `NetreoEndpoint.deviceServices` path (`/fw/index.php?r=restful/devices/services`)
- POST form body: `password=<apiKey>`, `name=<deviceName>`, `pin=<pin>`
- Parse response to count entries where `enabled == true` and `status == "ok"` (or equivalent OK indicator)
- Returns the integer count of enabled+OK service checks

### 4b. Shared Threshold Cache

Add a lightweight `ThresholdCache` class (or `@MainActor` singleton) with:

```swift
@MainActor
final class ThresholdCache: ObservableObject {
    static let shared = ThresholdCache()
    @Published private(set) var counts: [String: Int] = [:]
    private var lastFetched: Date? = nil
    private let staleDuration: TimeInterval = 600 // 10 minutes

    func refresh(using service: NetreoAPIService) async {
        guard lastFetched == nil || Date().timeIntervalSince(lastFetched!) > staleDuration else { return }
        if let fresh = try? await service.fetchThresholdCounts() {
            counts = fresh
            lastFetched = Date()
        }
    }

    func count(for deviceName: String) -> Int {
        counts[deviceName] ?? 0
    }
}
```

`ThresholdCache.shared.refresh(using:)` is called from `DeviceListViewModel` and `DeviceDetailViewModel` on each load.

### 4c. DeviceDetailViewModel — HEALTHY Count

Replace the binary formula with:

```
healthy = max(0, thresholdCount + okServiceChecks − activeIncidentCount)
```

Where:
- `thresholdCount = ThresholdCache.shared.count(for: device.name)`
- `okServiceChecks` = result of `fetchDeviceServices(deviceName:)`, loaded concurrently with incidents on device detail open
- `activeIncidentCount` = incidents where `status != .acknowledged` (i.e. open, non-ACK)

New published properties in `DeviceDetailViewModel`:
- `@Published var okServiceChecks: Int = 0`
- `@Published var isLoadingServices: Bool = false`

Both `loadIncidents()` and `loadServices()` are called concurrently via `async let`.

### 4d. DeviceListView — Per-Row Alarm Badges

Add alarm badge strip to each device row. Badges use the same color scheme as `GroupListView` (green/blue/yellow/orange/red).

**Data source:** `IncidentListViewModel.incidents` is already available globally via the shared `incidentViewModel` passed into `DeviceListView`. A new helper:

```swift
struct DeviceAlarmCounts {
    let healthy: Int   // ThresholdCache[name] - activeIncidents (0 if cache empty)
    let ack: Int
    let warning: Int
    let critical: Int
}

func alarmCounts(for deviceName: String, incidents: [NetreoIncident]) -> DeviceAlarmCounts
```

Maps `incidents` by `device` (case-insensitive match on device name) into severity buckets.

**`DeviceListView` changes:**
- Add `let incidentViewModel: IncidentListViewModel` parameter; update call site in `ContentView.mainTabs` from `DeviceListView(apiService: service)` to `DeviceListView(apiService: service, incidentViewModel: incidentViewModel)`
- Each `DeviceRow` receives `DeviceAlarmCounts` and renders 4 colored badge columns (HEALTHY / ACK / WARNING / CRITICAL)
- HEALTHY badge shows `—` (em-dash, `.secondary` color) when `ThresholdCache.shared.counts.isEmpty` (cache not yet loaded)
- Badges with value `0` render as grey text with no colored background (same rule as `GroupListView`)

**`ThresholdCache.shared.refresh(using:)` called from `DeviceListViewModel.load()`** so thresholds are populated whenever the device list refreshes.

---

## File Impact Summary

| File | Change |
|---|---|
| `ContentView.swift` | Middleware guard, server name AppStorage, pass incidentViewModel to DeviceListView |
| `Services/NetreoAPIService.swift` | `fetchThresholdCounts()`, `fetchDeviceServices()` |
| `Services/DeepLinkHandler.swift` | Remove auto-switch on import |
| `Views/AutoRefreshButton.swift` | M:SS countdown text, 32×32 frame |
| `Views/SettingsView.swift` | Radio button, inline delete, connection badge, server name subtitle |
| `Views/ServerConfigView.swift` | Remove direct-BHNM test fallback |
| `Views/DashboardView.swift` | Server name subtitle in principal toolbar |
| `Views/IncidentListView.swift` | Server name subtitle in principal toolbar |
| `Views/DeviceListView.swift` | Server name subtitle, accept incidentViewModel, alarm badges per row |
| `Views/DeviceDetailView.swift` | No change (alarmBar already exists) |
| `ViewModels/DeviceDetailViewModel.swift` | New HEALTHY formula, okServiceChecks loading |
| `ViewModels/DeviceListViewModel.swift` | Call ThresholdCache.refresh() on load |
| `Models/ThresholdCache.swift` | New file — shared cache singleton |

---

## Out of Scope

- Device list HEALTHY badge when threshold cache is unavailable (shows `—`, not computed from incidents alone)
- Threshold cache persistence across app restarts (in-memory only; re-fetched on next load)
- Per-device threshold breakdown (only total count per device name is used)
