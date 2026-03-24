# Performance On-Demand & Device List Limit — Design Spec

**Date:** 2026-03-24
**Scope:** Two related improvements to `DeviceDetailView` and `DeviceListView`:
1. Replace the always-loaded performance bars with dynamically-discovered, on-demand collapsible metric cards (Swift Charts histogram + current/avg/max), with Latency auto-loaded.
2. Cap the device list at a user-configurable count (default 20, max 100) to keep the devices screen fast.

---

## 1. Performance Cards — Overview

### Behaviour

- On view appear, the app discovers what metric categories and instances are available on that specific device via the BHNM API.
- **Latency** is the only category that auto-loads its time-series data and renders expanded.
- Every other instance card sits collapsed (title + chevron). No time-series API call is made until the user taps the card.
- Tapping a collapsed card triggers a `fetchTimeSeries` call; the card expands to show a line chart + stat tiles once data arrives.
- Tapping an already-expanded card collapses it (no re-fetch).
- A time frame picker (4 segments) on each expanded card lets the user re-fetch with a different window.

### Time Frame Options

Exactly the values BHNM accepts for `timeFrameFilterValue`:

| Display | API value |
|---|---|
| 1h | `Last Hour` |
| 2h | `Last 2 Hours` |
| 5h | `Last 5 Hours` |
| 24h | `Last 24 Hours` |

Default: `Last 24 Hours`.

---

## 2. Data Models

```swift
struct PerformanceCategory {
    let id: String    // e.g. "1", "5", "interfaces"
    let name: String  // e.g. "CPU", "Latency", "Network"
}

struct PerformanceInstance {
    let key: String        // unique; interfaces suffixed "-in"/"-out" to disambiguate
    let title: String      // e.g. "CPU Utilization", "eth0 — In"
    let unit: String       // e.g. "%", "s"
    let statGroup: String  // category name as expected by metricFilterStatGroup
    let categoryId: String
    let valueKey: String   // "value1" (default) or "value2" (outbound interface traffic)
}

struct PerformanceDataPoint {
    let timestamp: Date
    let value: Double
}

enum TimeFrame: String, CaseIterable {
    case lastHour      = "Last Hour"
    case last2Hours    = "Last 2 Hours"
    case last5Hours    = "Last 5 Hours"
    case last24Hours   = "Last 24 Hours"

    var displayName: String {
        switch self {
        case .lastHour:    return "1h"
        case .last2Hours:  return "2h"
        case .last5Hours:  return "5h"
        case .last24Hours: return "24h"
        }
    }
}

struct MetricCardState {
    let instance: PerformanceInstance
    var isExpanded: Bool = false
    var isLoading: Bool = false
    var hasBeenFetched: Bool = false  // true after any completed fetch (even empty/error)
    var data: [PerformanceDataPoint] = []
    var selectedTimeFrame: TimeFrame = .last24Hours
    var error: String? = nil

    var current: Double? { data.last?.value }
    var average: Double? {
        guard !data.isEmpty else { return nil }
        return data.map(\.value).reduce(0, +) / Double(data.count)
    }
    var max: Double? { data.map(\.value).max() }
}
```

---

## 3. New API Methods (NetreoAPIService)

### 3.1 `findDeviceIndex(name:) async throws -> String?`

```
POST /fw/index.php?r=restful/devices/find
Body: password=<key>&name=<deviceName>
```

Returns the `dev_index` string from the first result, or `nil` if not found.

### 3.2 `fetchPerformanceCategories(deviceId:) async throws -> [PerformanceCategory]`

```
POST /fw/index.php?r=restful/devices/performance-category
Body: password=<key>&device_id=<devIndex>
```

Maps response array: `id` from `"id"` field — parse as `(dict["id"] as? String) ?? (dict["id"] as? Int).map(String.init) ?? ""`; `name` from `"category"` or `"cat"` field.

### 3.3 `fetchPerformanceInstances(deviceId:category:) async throws -> [PerformanceInstance]`

```
POST /fw/index.php?r=restful/devices/performance-instance-per-category
Body: password=<key>&device_id=<devIndex>&id=<category.id>
```

**Non-interface entries** (`"type" != "interface"`):
- `key`: parse as `(dict["key"] as? String) ?? (dict["key"] as? Int).map(String.init) ?? ""`
- `title`: `"title"` field
- `unit`: `"unit"` field
- `statGroup`: `category.name`
- `categoryId`: `category.id`
- `valueKey`: `"value1"`

**Interface entries** (`"type" == "interface"`):
Each entry produces **two** `PerformanceInstance` structs — one for inbound, one for outbound:

1. **Inbound:**
   - `key`: `"\(rawKey)-in"` where `rawKey` is parsed as above — the `-in` suffix is **required** to ensure `cardStates` dictionary keys are unique (the raw numeric key is shared between both interface instances)
   - `title`: `"\(description) — In"`
   - `unit`: `entry.bandwidth.unit`
   - `statGroup`: `category.name`
   - `categoryId`: `category.id`
   - `valueKey`: `"value1"`

2. **Outbound:**
   - `key`: `"\(rawKey)-out"`
   - `title`: `"\(description) — Out"`
   - `unit`: `entry.bandwidth.unit`
   - `statGroup`: `category.name`
   - `categoryId`: `category.id`
   - `valueKey`: `"value2"`

Interface `errors` sub-object is omitted (out of scope).

### 3.4 `fetchTimeSeries(deviceName:instance:timeFrame:) async throws -> [PerformanceDataPoint]`

```
POST /fw/index.php?r=restful/devices/get-time-series-metrics
Body: password=<key>
      &groupFilterBy=device
      &groupFilterValue=<deviceName>
      &metricFilterStatGroup=<instance.statGroup>
      &metricFilterUnits=<instance.unit>
      &timeFrameFilterBy=time_offset
      &timeFrameFilterValue=<timeFrame.rawValue>
      &returnFormatFilterBy=average
```

Maps `metrics` array: `timestamp` from `"timeStamp"` (Unix string → `Date`), `value` from `instance.valueKey` field (String → Double). Skip rows where the `valueKey` field is absent or null.

### 3.5 `fetchDevicesPage(limit:) async throws -> [NetreoDevice]`

A **new** method, separate from the existing `fetchDevices()`. Uses the same two-shape JSON parsing as `fetchDevices()` (handles both `{"devices":[...]}` and `{"data":{"devices":[...]}}` response envelopes). Appends `&recordStart=0&recordCount=<limit>` to the POST body.

The existing `fetchDevices()` remains **unchanged and uncapped** — it is still called by all tactical overview methods (`fetchCategorySummaries`, `fetchSiteSummaries`, `fetchBusinessWorkflowSummaries`) which must see the full device estate.

---

## 4. DeviceDetailViewModel Changes

### Properties removed
- `cpuMetrics`, `memoryMetrics`, `diskMetrics`, `interfaceMetrics`
- `isLoadingPerformance`, `isLoadingInterfaces`
- `performanceError`, `interfacesError`

### Properties added
```swift
@Published var categories: [PerformanceCategory] = []
@Published var cardStates: [String: MetricCardState] = [:]   // keyed by instance.key
@Published var isLoadingCategories = false
@Published var categoriesError: String? = nil

private var devIndex: String? = nil
```

### `load()` — unchanged shape
```
withTaskGroup {
    loadIncidents()            // unchanged
    loadPerformanceStructure()
}
```

### `loadPerformanceStructure()`
1. Set `isLoadingCategories = true`
2. Call `findDeviceIndex(name:)` → store in `devIndex`; on failure set `categoriesError`, return
3. Call `fetchPerformanceCategories(deviceId:)` → store in `categories`
4. `withTaskGroup`: call `fetchPerformanceInstances(deviceId:category:)` for all categories in parallel; collect all instances; populate `cardStates` with one `MetricCardState` per instance (all `isExpanded=false`, `hasBeenFetched=false`)
5. Set `isLoadingCategories = false`
6. Identify Latency: any category where `category.name.lowercased().contains("latency")`. For each instance in Latency categories: fire `Task { await self.tapCard(instanceKey: instance.key) }` (non-blocking — returns immediately, loads concurrently)

### `tapCard(instanceKey:) async`
```
guard let state = cardStates[key] else { return }
guard !state.isLoading else { return }   // prevent duplicate concurrent fetches

if state.hasBeenFetched {
    cardStates[key]?.isExpanded.toggle()
    return
}

cardStates[key]?.isLoading = true
do {
    let data = try await apiService.fetchTimeSeries(deviceName:instance:timeFrame:)
    cardStates[key]?.data = data
    cardStates[key]?.hasBeenFetched = true
    cardStates[key]?.isExpanded = true
    cardStates[key]?.isLoading = false
} catch {
    cardStates[key]?.error = error.localizedDescription
    cardStates[key]?.hasBeenFetched = true
    cardStates[key]?.isLoading = false
}
```

### `changeTimeFrame(_ tf: TimeFrame, instanceKey: String) async`
```
guard let state = cardStates[key], !state.isLoading else { return }
cardStates[key]?.selectedTimeFrame = tf
cardStates[key]?.isLoading = true
// Do NOT clear data yet — keep existing data visible until new data arrives
do {
    let newData = try await apiService.fetchTimeSeries(...)
    cardStates[key]?.data = newData    // replace only on success
    cardStates[key]?.error = nil
    cardStates[key]?.isLoading = false
} catch {
    cardStates[key]?.error = error.localizedDescription
    cardStates[key]?.isLoading = false
    // existing data remains visible; error shown as overlay
}
```

---

## 5. DeviceDetailView Changes

### Removed
- `performanceSection` (bars)
- `interfacesSection`
- `metricRow`, `diskRow`, `formatBytes`, `formatBps` helpers

### `performanceSection` (new)
```
if isLoadingCategories → single ProgressView
else if categoriesError → error text
else →
  ForEach categories:
    sectionHeader(category.name)
    ForEach instances in category (ordered by key):
      MetricCard(
        state: $cardStates[instance.key],
        onTap: { Task { await vm.tapCard(instanceKey: key) } },
        onTimeFrameChange: { tf in Task { await vm.changeTimeFrame(tf, instanceKey: key) } }
      )
```

### `MetricCard` sub-view
A standalone `View` struct accepting a `Binding<MetricCardState>`, `onTap: () -> Void`, `onTimeFrameChange: (TimeFrame) -> Void`.

**Collapsed row:**
```swift
HStack {
    statusDot(state: state)
    Text(instance.title).font(.subheadline)
    Spacer()
    if state.isLoading {
        ProgressView().controlSize(.small)
    } else {
        Image(systemName: state.isExpanded ? "chevron.up" : "chevron.down")
            .foregroundColor(.secondary)
    }
}
.padding(.horizontal).padding(.vertical, 10)
.contentShape(Rectangle())
.onTapGesture { onTap() }
```

**Expanded content (visible when `state.isExpanded`):**
```swift
VStack(spacing: 8) {
    // Time frame picker
    Picker("", selection: $state.selectedTimeFrame) {
        ForEach(TimeFrame.allCases, id: \.self) { tf in
            Text(tf.displayName).tag(tf)
        }
    }
    .pickerStyle(.segmented)
    .padding(.horizontal)
    .onChange(of: state.selectedTimeFrame) { newValue in   // single-arg form: iOS 16 compatible
        onTimeFrameChange(newValue)
    }

    if state.data.isEmpty && state.error == nil {
        // Still loading or genuinely empty
        Text("No data available").font(.caption).foregroundColor(.secondary).padding()
    } else {
        // Chart
        Chart(state.data, id: \.timestamp) { point in
            LineMark(
                x: .value("Time", point.timestamp),
                y: .value(instance.unit, point.value)
            )
        }
        .frame(height: 120)
        .padding(.horizontal)

        // Stat tiles
        HStack {
            statTile("CURRENT", formatValue(state.current, instance.unit))
            Divider()
            statTile("AVG",     formatValue(state.average, instance.unit))
            Divider()
            statTile("MAX",     formatValue(state.max, instance.unit))
        }
        .frame(height: 56)
    }

    // Error overlay (shown in addition to stale data if re-fetch failed)
    if let err = state.error {
        Text(err).font(.caption2).foregroundColor(.red).padding(.horizontal)
    }
}
.padding(.bottom, 8)
```

**`formatValue(_ value: Double?, unit: String) -> String`**
- `nil` → `"—"`
- `unit == "s"`:
  - `value < 0.001` → `"\(Int(value * 1_000_000)) µs"`
  - `value < 1` → `String(format: "%.1f ms", value * 1000)`
  - else → `String(format: "%.2f s", value)`
- `unit == "%"` → `String(format: "%.1f%%", value)`
- `unit == "B"` → formatBytes (existing logic)
- else → `String(format: "%.2f \(unit)", value)`

**`statusDot` color** (based on `state.current ?? 0`):
- `!state.hasBeenFetched` → `.gray`
- `unit == "%"`: < 60 → green, < 80 → orange, ≥ 80 → red
- `unit == "s"`: < 0.01 → green, < 0.1 → orange, ≥ 0.1 → red
- else → `.blue`

---

## 6. SettingsView — Device List Limit

New "Devices" section in `SettingsView`:
```swift
@AppStorage("maxDevicesCount") var maxDevicesCount: Int = 20

Section("Devices") {
    Stepper("Load up to \(maxDevicesCount) devices",
            value: $maxDevicesCount, in: 10...100, step: 10)
}
```

---

## 7. DeviceListViewModel & DeviceListView Changes

### DeviceListViewModel

Replace the existing `loadDevices()` signature:
```swift
// New: stores limit so internal callers (addDevice/deleteDevice/renameDevice) reuse last known limit
private var currentLimit: Int = 20

func loadDevices(limit: Int? = nil) async {
    if let limit { currentLimit = limit }
    isLoading = true
    errorMessage = nil
    do {
        devices = try await apiService.fetchDevicesPage(limit: currentLimit)
    } catch {
        errorMessage = error.localizedDescription
    }
    isLoading = false
}
```

Internal callers `addDevice`, `deleteDevice`, `renameDevice` continue to call `await loadDevices()` (no argument) — they reuse `currentLimit`.

### DeviceListView

Add `@AppStorage("maxDevicesCount") private var maxDevicesCount: Int = 20`.

All five existing call sites that call `viewModel.loadDevices()` must be updated to `viewModel.loadDevices(limit: maxDevicesCount)`:

| Location | Current | Updated |
|---|---|---|
| `.task { ... }` (initial load, line 77) | `await viewModel.loadDevices()` | `await viewModel.loadDevices(limit: maxDevicesCount)` |
| `ConnectionBadgeButton` action (line 29) | `Task { await viewModel.loadDevices() }` | `Task { await viewModel.loadDevices(limit: maxDevicesCount) }` |
| `AutoRefreshButton` action (line 43) | `viewModel.loadDevices` (function reference) | Replace with closure: `{ Task { await viewModel.loadDevices(limit: maxDevicesCount) } }` — **note:** `AutoRefreshButton` expects `() -> Void`; wrap in a `Task` |
| `.refreshable` (line 50) | `await viewModel.loadDevices()` | `await viewModel.loadDevices(limit: maxDevicesCount)` |
| `.task(id:)` reconnect (line 72) | `Task { await viewModel.loadDevices() }` | `Task { await viewModel.loadDevices(limit: maxDevicesCount) }` |

Add `.onChange` to react to setting changes (iOS 16-compatible single-argument form):
```swift
.onChange(of: maxDevicesCount) { newLimit in
    Task { await viewModel.loadDevices(limit: newLimit) }
}
```

---

## 8. Files Changed

| Action | File | Change |
|---|---|---|
| Modify | `BeNeM/Services/NetreoAPIService.swift` | Add `findDeviceIndex`, `fetchPerformanceCategories`, `fetchPerformanceInstances`, `fetchTimeSeries`; add `fetchDevicesPage(limit:)`; `fetchDevices()` unchanged |
| Modify | `BeNeM/ViewModels/DeviceDetailViewModel.swift` | Replace performance state with category/card state; add `tapCard`, `changeTimeFrame` |
| Modify | `BeNeM/Views/DeviceDetailView.swift` | Replace bars + interfaces section with dynamic MetricCard list |
| Modify | `BeNeM/ViewModels/DeviceListViewModel.swift` | Replace `loadDevices()` with `loadDevices(limit:?)`; add `currentLimit` |
| Modify | `BeNeM/Views/DeviceListView.swift` | Add `@AppStorage("maxDevicesCount")`; update all 5 call sites; add `.onChange` |
| Modify | `BeNeM/Views/SettingsView.swift` | Add "Devices" section with Stepper |

---

## 9. Out of Scope

- Caching time-series data across navigation (data is re-fetched on each view appear)
- Pagination / "load more" for the device list (limit is a hard cap, not a paginator)
- Interface `errors` metric cards
