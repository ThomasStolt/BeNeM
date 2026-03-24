# Performance On-Demand & Device List Limit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace always-loaded performance bars in DeviceDetailView with dynamically-discovered on-demand metric cards (Swift Charts, current/avg/max), auto-load Latency only, and add a user-configurable device list limit (default 20, max 100).

**Architecture:** Two independent feature tracks share NetreoAPIService. Track A (Tasks 1–4) adds `fetchDevicesPage(limit:)`, wires it through DeviceListViewModel and DeviceListView, and exposes a Stepper in Settings. Track B (Tasks 5–8) adds four new discovery/time-series API methods, rewrites DeviceDetailViewModel with per-card state, and replaces the performance bars with collapsible MetricCard views backed by Swift Charts. Both tracks can be built and verified independently.

**Tech Stack:** Swift 5.9, SwiftUI, async/await, Swift Charts (iOS 16+), `withTaskGroup` for parallel fetches, `@AppStorage` for the device limit setting, form-urlencoded POST matching existing patterns.

---

## File Map

| Action | File | Responsibility |
|---|---|---|
| Modify | `BeNeM/Services/NetreoAPIService.swift` | Add `fetchDevicesPage(limit:)`, `findDeviceIndex`, `fetchPerformanceCategories`, `fetchPerformanceInstances`, `fetchTimeSeries`; add new structs `PerformanceCategory`, `PerformanceInstance`, `PerformanceDataPoint` |
| Modify | `BeNeM/ViewModels/DeviceListViewModel.swift` | Replace `loadDevices()` with `loadDevices(limit:?)` backed by `currentLimit` |
| Modify | `BeNeM/Views/DeviceListView.swift` | Add `@AppStorage("maxDevicesCount")`; update all 5 call sites; add `.onChange` reload |
| Modify | `BeNeM/Views/SettingsView.swift` | Add "Devices" section with Stepper |
| Modify | `BeNeM/ViewModels/DeviceDetailViewModel.swift` | Full rewrite: replace old perf properties with `categories`/`cardStates`; add `TimeFrame` enum, `MetricCardState` struct, `tapCard`, `changeTimeFrame` |
| Modify | `BeNeM/Views/DeviceDetailView.swift` | Remove bars/interfaces sections; add `MetricCard` sub-view and dynamic performance section |

---

## Task 1: Add `fetchDevicesPage(limit:)` to NetreoAPIService

**Files:**
- Modify: `BeNeM/Services/NetreoAPIService.swift`

- [ ] **Step 1: Add `fetchDevicesPage(limit:)` directly after `fetchDevices()`**

Open `NetreoAPIService.swift`. After the closing `}` of `fetchDevices()` (line ~65), add:

```swift
func fetchDevicesPage(limit: Int) async throws -> [NetreoDevice] {
    guard let url = URL(string: "\(configuration.baseURL)/fw/index.php?r=restful/devices/list") else { return [] }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    var params = [URLQueryItem(name: "password", value: configuration.apiKey)]
    if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
    params.append(URLQueryItem(name: "recordStart", value: "0"))
    params.append(URLQueryItem(name: "recordCount", value: String(limit)))
    request.httpBody = formEncodedBody(params)
    let (data, _) = try await urlSession.data(for: request)
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
    let devicesArray: [[String: Any]]
    if let arr = json["devices"] as? [[String: Any]] {
        devicesArray = arr
    } else if let nested = json["data"] as? [String: Any],
              let arr = nested["devices"] as? [[String: Any]] {
        devicesArray = arr
    } else {
        return []
    }
    return devicesArray.compactMap { parseRESTfulDevice(from: $0) }
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM
xcodebuild -scheme BeNeM -destination 'generic/platform=iOS' build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add BeNeM/Services/NetreoAPIService.swift
git commit -m "feat: add fetchDevicesPage(limit:) to NetreoAPIService"
```

---

## Task 2: Update DeviceListViewModel

**Files:**
- Modify: `BeNeM/ViewModels/DeviceListViewModel.swift`

- [ ] **Step 1: Add `currentLimit` and replace `loadDevices()`**

Replace the entire `loadDevices()` method and add the `currentLimit` property:

```swift
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

`addDevice`, `deleteDevice`, and `renameDevice` continue calling `await loadDevices()` with no argument — they reuse `currentLimit` automatically.

- [ ] **Step 2: Build**

```bash
xcodebuild -scheme BeNeM -destination 'generic/platform=iOS' build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add BeNeM/ViewModels/DeviceListViewModel.swift
git commit -m "feat: add currentLimit and loadDevices(limit:) to DeviceListViewModel"
```

---

## Task 3: Update DeviceListView — wire limit to all call sites

**Files:**
- Modify: `BeNeM/Views/DeviceListView.swift`

- [ ] **Step 1: Add `@AppStorage` property**

After the existing `@AppStorage("refresh_interval")` line, add:

```swift
@AppStorage("maxDevicesCount") private var maxDevicesCount: Int = 20
```

- [ ] **Step 2: Update all five `loadDevices()` call sites to pass the limit**

There are exactly 5 call sites. Update each:

**a) Initial load `.task` (bottom of `body`, after `NavigationView`):**
```swift
// Before:
.task {
    connectionStatus = .checking
    await viewModel.loadDevices()
}
// After:
.task {
    connectionStatus = .checking
    await viewModel.loadDevices(limit: maxDevicesCount)
}
```

**b) `ConnectionBadgeButton` action (inside toolbar):**
```swift
// Before:
ConnectionBadgeButton(status: connectionStatus) {
    Task { await viewModel.loadDevices() }
}
// After:
ConnectionBadgeButton(status: connectionStatus) {
    Task { await viewModel.loadDevices(limit: maxDevicesCount) }
}
```

**c) `AutoRefreshButton` action — function reference must become a closure:**
```swift
// Before:
AutoRefreshButton(
    interval: refreshInterval,
    isLoading: viewModel.isLoading,
    action: viewModel.loadDevices
)
// After:
AutoRefreshButton(
    interval: refreshInterval,
    isLoading: viewModel.isLoading,
    action: { await viewModel.loadDevices(limit: maxDevicesCount) }
)
```

**d) `.refreshable`:**
```swift
// Before:
.refreshable { await viewModel.loadDevices() }
// After:
.refreshable { await viewModel.loadDevices(limit: maxDevicesCount) }
```

**e) `.task(id: connectionStatus)` reconnect:**
```swift
// Before:
Task { await viewModel.loadDevices() }
// After:
Task { await viewModel.loadDevices(limit: maxDevicesCount) }
```

- [ ] **Step 3: Add `.onChange` to reload when the setting changes**

Add after the existing `.onChange(of: viewModel.isLoading)`:

```swift
.onChange(of: maxDevicesCount) { newLimit in
    Task { await viewModel.loadDevices(limit: newLimit) }
}
```

- [ ] **Step 4: Build**

```bash
xcodebuild -scheme BeNeM -destination 'generic/platform=iOS' build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add BeNeM/Views/DeviceListView.swift
git commit -m "feat: wire maxDevicesCount limit through DeviceListView"
```

---

## Task 4: Add "Devices" section to SettingsView

**Files:**
- Modify: `BeNeM/Views/SettingsView.swift`

- [ ] **Step 1: Add `@AppStorage` property and Devices section**

Add the property after the existing `@AppStorage` declarations at the top of `SettingsView`:

```swift
@AppStorage("maxDevicesCount") private var maxDevicesCount: Int = 20
```

Add the new section inside the `Form`, after the "Refresh" section:

```swift
Section(header: Text("Devices")) {
    Stepper("Load up to \(maxDevicesCount) devices",
            value: $maxDevicesCount, in: 10...100, step: 10)
    Text("Limits how many devices are loaded in the Devices tab. Increase if you have a large estate.")
        .font(.caption)
        .foregroundColor(.secondary)
}
```

- [ ] **Step 2: Build and deploy**

```bash
xcodebuild -scheme BeNeM -destination 'generic/platform=iOS' build 2>&1 | tail -5
./build_and_deploy.sh
```

Expected: `BUILD SUCCEEDED`, app installs on device.

Smoke test:
- Open Settings → should see "Devices" section with Stepper defaulting to 20
- Step up/down — Devices tab should reload and show more/fewer rows

- [ ] **Step 3: Commit**

```bash
git add BeNeM/Views/SettingsView.swift
git commit -m "feat: add device list limit stepper to SettingsView"
```

---

## Task 5: Add new performance models and API structs to NetreoAPIService

**Files:**
- Modify: `BeNeM/Services/NetreoAPIService.swift`

- [ ] **Step 1: Add new structs at the top of the file, after the existing `PerformanceMetric` struct**

```swift
struct PerformanceCategory {
    let id: String
    let name: String
}

struct PerformanceInstance {
    let key: String        // unique; interface instances are suffixed "-in" or "-out"
    let title: String
    let unit: String
    let statGroup: String  // value passed to metricFilterStatGroup
    let categoryId: String
    let valueKey: String   // "value1" or "value2" (outbound interface)
}

struct PerformanceDataPoint {
    let timestamp: Date
    let value: Double
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -scheme BeNeM -destination 'generic/platform=iOS' build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add BeNeM/Services/NetreoAPIService.swift
git commit -m "feat: add PerformanceCategory, PerformanceInstance, PerformanceDataPoint structs"
```

---

## Task 6: Add three discovery API methods to NetreoAPIService

**Files:**
- Modify: `BeNeM/Services/NetreoAPIService.swift`

Add these three methods after `fetchDevicesPage(limit:)`. The fourth method (`fetchTimeSeries`) references `TimeFrame`, which is defined in Task 7 — it is added in Task 7 Step 2 after `TimeFrame` exists in the module.

- [ ] **Step 1: Add `findDeviceIndex(name:)`**

```swift
func findDeviceIndex(name: String) async throws -> String? {
    guard let url = URL(string: "\(configuration.baseURL)/fw/index.php?r=restful/devices/find") else { return nil }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    var params = [
        URLQueryItem(name: "password", value: configuration.apiKey),
        URLQueryItem(name: "name",     value: name),
    ]
    if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
    request.httpBody = formEncodedBody(params)
    let (data, _) = try await urlSession.data(for: request)
    guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
          let first = arr.first else { return nil }
    return first["dev_index"] as? String
}
```

- [ ] **Step 2: Add `fetchPerformanceCategories(deviceId:)`**

```swift
func fetchPerformanceCategories(deviceId: String) async throws -> [PerformanceCategory] {
    guard let url = URL(string: "\(configuration.baseURL)/fw/index.php?r=restful/devices/performance-category") else { return [] }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    var params = [
        URLQueryItem(name: "password",   value: configuration.apiKey),
        URLQueryItem(name: "device_id",  value: deviceId),
    ]
    if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
    request.httpBody = formEncodedBody(params)
    let (data, _) = try await urlSession.data(for: request)
    guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
    return arr.compactMap { dict -> PerformanceCategory? in
        let rawId = (dict["id"] as? String) ?? (dict["id"] as? Int).map(String.init)
        guard let id = rawId else { return nil }
        let name = (dict["category"] as? String) ?? (dict["cat"] as? String) ?? ""
        guard !name.isEmpty else { return nil }
        return PerformanceCategory(id: id, name: name)
    }
}
```

- [ ] **Step 3: Add `fetchPerformanceInstances(deviceId:category:)`**

```swift
func fetchPerformanceInstances(deviceId: String, category: PerformanceCategory) async throws -> [PerformanceInstance] {
    guard let url = URL(string: "\(configuration.baseURL)/fw/index.php?r=restful/devices/performance-instance-per-category") else { return [] }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    var params = [
        URLQueryItem(name: "password",  value: configuration.apiKey),
        URLQueryItem(name: "device_id", value: deviceId),
        URLQueryItem(name: "id",        value: category.id),
    ]
    if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
    request.httpBody = formEncodedBody(params)
    let (data, _) = try await urlSession.data(for: request)
    guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

    var instances: [PerformanceInstance] = []
    for dict in arr {
        let rawKey = (dict["key"] as? String) ?? (dict["key"] as? Int).map(String.init) ?? ""
        let type_ = dict["type"] as? String ?? ""

        if type_ == "interface" {
            // Interface entries produce two instances: inbound and outbound
            let description = dict["description"] as? String ?? rawKey
            let bwUnit = (dict["bandwidth"] as? [String: Any])?["unit"] as? String ?? "%"
            instances.append(PerformanceInstance(
                key: "\(rawKey)-in",
                title: "\(description) — In",
                unit: bwUnit,
                statGroup: category.name,
                categoryId: category.id,
                valueKey: "value1"
            ))
            instances.append(PerformanceInstance(
                key: "\(rawKey)-out",
                title: "\(description) — Out",
                unit: bwUnit,
                statGroup: category.name,
                categoryId: category.id,
                valueKey: "value2"
            ))
        } else {
            let title = dict["title"] as? String ?? rawKey
            let unit  = dict["unit"]  as? String ?? ""
            instances.append(PerformanceInstance(
                key: rawKey,
                title: title,
                unit: unit,
                statGroup: category.name,
                categoryId: category.id,
                valueKey: "value1"
            ))
        }
    }
    return instances
}
```

- [ ] **Step 4: Build**

```bash
xcodebuild -scheme BeNeM -destination 'generic/platform=iOS' build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add BeNeM/Services/NetreoAPIService.swift
git commit -m "feat: add findDeviceIndex, fetchPerformanceCategories, fetchPerformanceInstances to NetreoAPIService"
```

---

## Task 7: Rewrite DeviceDetailViewModel

**Files:**
- Modify: `BeNeM/ViewModels/DeviceDetailViewModel.swift`

Replace the entire file contents with the following. This removes all old performance properties and adds the new category/card-state model.

- [ ] **Step 1: Replace the file**

```swift
import Foundation

// MARK: - TimeFrame

enum TimeFrame: String, CaseIterable {
    case lastHour    = "Last Hour"
    case last2Hours  = "Last 2 Hours"
    case last5Hours  = "Last 5 Hours"
    case last24Hours = "Last 24 Hours"

    var displayName: String {
        switch self {
        case .lastHour:    return "1h"
        case .last2Hours:  return "2h"
        case .last5Hours:  return "5h"
        case .last24Hours: return "24h"
        }
    }
}

// MARK: - MetricCardState

struct MetricCardState {
    let instance: PerformanceInstance
    var isExpanded: Bool = false
    var isLoading: Bool = false
    var hasBeenFetched: Bool = false
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

// MARK: - DeviceDetailViewModel

@MainActor
class DeviceDetailViewModel: ObservableObject {
    @Published var incidents: [NetreoIncident] = []
    @Published var isLoadingIncidents = true
    @Published var incidentsError: String?

    @Published var categories: [PerformanceCategory] = []
    @Published var cardStates: [String: MetricCardState] = [:]
    @Published var isLoadingCategories = false
    @Published var categoriesError: String?

    private var devIndex: String?
    private let apiService: NetreoAPIService
    let device: NetreoDevice

    init(device: NetreoDevice, apiService: NetreoAPIService) {
        self.device = device
        self.apiService = apiService
    }

    func load() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadIncidents() }
            group.addTask { await self.loadPerformanceStructure() }
        }
    }

    // MARK: - Incidents (unchanged logic)

    private func loadIncidents() async {
        isLoadingIncidents = true
        incidentsError = nil
        do {
            let all = try await apiService.fetchIncidents()
            let deviceName = device.name ?? device.ip
            incidents = all.filter { incident in
                let incName = incident.deviceName ?? ""
                let incIP   = incident.deviceIP   ?? ""
                return incName.caseInsensitiveCompare(deviceName) == .orderedSame
                    || incName.caseInsensitiveCompare(device.ip)  == .orderedSame
                    || incIP   == device.ip
                    || incName.lowercased().components(separatedBy: ".").first
                       == deviceName.lowercased().components(separatedBy: ".").first
            }
        } catch {
            incidentsError = error.localizedDescription
        }
        isLoadingIncidents = false
    }

    // MARK: - Performance Structure

    private func loadPerformanceStructure() async {
        isLoadingCategories = true
        categoriesError = nil
        let name = device.name ?? device.ip

        // 1. Resolve dev_index
        guard let index = try? await apiService.findDeviceIndex(name: name) else {
            categoriesError = "Could not resolve device index for \"\(name)\""
            isLoadingCategories = false
            return
        }
        devIndex = index

        // 2. Fetch categories
        guard let cats = try? await apiService.fetchPerformanceCategories(deviceId: index),
              !cats.isEmpty else {
            categoriesError = "No performance categories found"
            isLoadingCategories = false
            return
        }
        categories = cats

        // 3. Fetch instances for all categories in parallel
        var allInstances: [PerformanceInstance] = []
        await withTaskGroup(of: [PerformanceInstance].self) { group in
            for cat in cats {
                group.addTask {
                    (try? await self.apiService.fetchPerformanceInstances(deviceId: index, category: cat)) ?? []
                }
            }
            for await instances in group {
                allInstances.append(contentsOf: instances)
            }
        }

        // Populate cardStates — all collapsed, no data yet
        var states: [String: MetricCardState] = [:]
        for instance in allInstances {
            states[instance.key] = MetricCardState(instance: instance)
        }
        cardStates = states
        isLoadingCategories = false

        // 4. Auto-load Latency instances
        let latencyInstances = allInstances.filter { instance in
            cats.first(where: { $0.id == instance.categoryId })?.name.lowercased().contains("latency") == true
        }
        for instance in latencyInstances {
            Task { await self.tapCard(instanceKey: instance.key) }
        }
    }

    // MARK: - Card Interactions

    func tapCard(instanceKey: String) async {
        guard let state = cardStates[instanceKey] else { return }
        guard !state.isLoading else { return }

        if state.hasBeenFetched {
            cardStates[instanceKey]?.isExpanded.toggle()
            return
        }

        cardStates[instanceKey]?.isLoading = true
        let name = device.name ?? device.ip
        do {
            let data = try await apiService.fetchTimeSeries(
                deviceName: name,
                instance: state.instance,
                timeFrame: state.selectedTimeFrame
            )
            cardStates[instanceKey]?.data = data
            cardStates[instanceKey]?.hasBeenFetched = true
            cardStates[instanceKey]?.isExpanded = true
            cardStates[instanceKey]?.isLoading = false
        } catch {
            cardStates[instanceKey]?.error = error.localizedDescription
            cardStates[instanceKey]?.hasBeenFetched = true
            cardStates[instanceKey]?.isLoading = false
        }
    }

    func changeTimeFrame(_ tf: TimeFrame, instanceKey: String) async {
        guard let state = cardStates[instanceKey], !state.isLoading else { return }
        cardStates[instanceKey]?.selectedTimeFrame = tf
        cardStates[instanceKey]?.isLoading = true
        let name = device.name ?? device.ip
        do {
            let newData = try await apiService.fetchTimeSeries(
                deviceName: name,
                instance: state.instance,
                timeFrame: tf
            )
            cardStates[instanceKey]?.data = newData
            cardStates[instanceKey]?.error = nil
            cardStates[instanceKey]?.isLoading = false
        } catch {
            cardStates[instanceKey]?.error = error.localizedDescription
            cardStates[instanceKey]?.isLoading = false
        }
    }
}
```

- [ ] **Step 2: Add `fetchTimeSeries` to NetreoAPIService**

Now that `TimeFrame` is defined in `DeviceDetailViewModel.swift`, add this method to `BeNeM/Services/NetreoAPIService.swift` after `fetchPerformanceInstances`:

```swift
func fetchTimeSeries(
    deviceName: String,
    instance: PerformanceInstance,
    timeFrame: TimeFrame
) async throws -> [PerformanceDataPoint] {
    let urlString = "\(configuration.baseURL)/fw/index.php?r=restful/devices/get-time-series-metrics"
    guard let url = URL(string: urlString) else { return [] }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    var params = [
        URLQueryItem(name: "password",               value: configuration.apiKey),
        URLQueryItem(name: "groupFilterBy",          value: "device"),
        URLQueryItem(name: "groupFilterValue",       value: deviceName),
        URLQueryItem(name: "metricFilterStatGroup",  value: instance.statGroup),
        URLQueryItem(name: "metricFilterUnits",      value: instance.unit),
        URLQueryItem(name: "timeFrameFilterBy",      value: "time_offset"),
        URLQueryItem(name: "timeFrameFilterValue",   value: timeFrame.rawValue),
        URLQueryItem(name: "returnFormatFilterBy",   value: "average"),
    ]
    if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
    request.httpBody = formEncodedBody(params)
    let (data, _) = try await urlSession.data(for: request)
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let metrics = json["metrics"] as? [[String: Any]] else { return [] }
    return metrics.compactMap { dict -> PerformanceDataPoint? in
        guard let tsString = dict["timeStamp"] as? String,
              let ts = Double(tsString) else { return nil }
        let rawValue = dict[instance.valueKey]
        let value: Double?
        if let s = rawValue as? String { value = Double(s) }
        else if let d = rawValue as? Double { value = d }
        else { return nil }
        guard let v = value else { return nil }
        return PerformanceDataPoint(timestamp: Date(timeIntervalSince1970: ts), value: v)
    }
}
```

- [ ] **Step 3: Build**

```bash
xcodebuild -scheme BeNeM -destination 'generic/platform=iOS' build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

Note: `DeviceDetailView.swift` still references the old properties (`cpuMetrics`, `isLoadingPerformance`, etc.) so you may see compiler errors in that file — those are expected and resolved in Task 8.

- [ ] **Step 4: Commit both files**

```bash
git add BeNeM/ViewModels/DeviceDetailViewModel.swift BeNeM/Services/NetreoAPIService.swift
git commit -m "feat: rewrite DeviceDetailViewModel with on-demand card state and add fetchTimeSeries"
```

---

## Task 8: Rewrite DeviceDetailView

**Files:**
- Modify: `BeNeM/Views/DeviceDetailView.swift`

Replace the entire file. This removes the performance bars, interfaces section, and all related helpers, and introduces the `MetricCard` sub-view backed by Swift Charts.

- [ ] **Step 1: Replace the file**

```swift
import SwiftUI
import Charts

struct DeviceDetailView: View {
    @StateObject private var viewModel: DeviceDetailViewModel

    init(device: NetreoDevice, apiService: NetreoAPIService) {
        _viewModel = StateObject(wrappedValue: DeviceDetailViewModel(device: device, apiService: apiService))
    }

    var body: some View {
        let device = viewModel.device
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                deviceHeaderCard(device)
                issuesSection
                performanceSection
            }
        }
        .navigationTitle(device.name ?? device.ip)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    // MARK: - Device Header Card

    private func deviceHeaderCard(_ device: NetreoDevice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(statusColor(device.status))
                    .frame(width: 14, height: 14)
                Text(device.name ?? device.ip)
                    .font(.title2).fontWeight(.semibold)
                Spacer()
                StatusBadge(status: device.status)
            }
            HStack(spacing: 6) {
                Text(device.ip)
                    .font(.caption).foregroundColor(.secondary)
                if let type = device.deviceType, !type.isEmpty {
                    Text("·").foregroundColor(.secondary).font(.caption)
                    Text(type).font(.caption).foregroundColor(.secondary)
                }
                if let site = device.siteID, !site.isEmpty {
                    Text("·").foregroundColor(.secondary).font(.caption)
                    Text(site).font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Current Issues

    private var issuesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Current Issues")
            if viewModel.isLoadingIncidents {
                HStack { Spacer(); ProgressView(); Spacer() }.padding()
            } else if let err = viewModel.incidentsError {
                Text(err).font(.caption).foregroundColor(.secondary).padding()
            } else if viewModel.incidents.isEmpty {
                Text("No active issues")
                    .font(.subheadline).foregroundColor(.secondary)
                    .padding()
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("TYPE").frame(width: 80, alignment: .leading)
                        Text("DESCRIPTION").frame(maxWidth: .infinity, alignment: .leading)
                        Text("DURATION").frame(width: 80, alignment: .trailing)
                    }
                    .font(.caption2).foregroundColor(.secondary)
                    .padding(.horizontal).padding(.top, 6).padding(.bottom, 4)
                    Divider()
                    ForEach(viewModel.incidents) { incident in
                        HStack(alignment: .top) {
                            Text(incident.category ?? incident.severity.rawValue.capitalized)
                                .font(.caption).foregroundColor(incident.severity.color)
                                .frame(width: 80, alignment: .leading)
                            Text(incident.summary)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(2)
                            Text(durationString(from: incident.startTime))
                                .font(.caption2).foregroundColor(.secondary)
                                .frame(width: 80, alignment: .trailing)
                        }
                        .padding(.horizontal).padding(.vertical, 6)
                        Divider().padding(.leading)
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
            }
        }
        .padding(.top, 16)
    }

    // MARK: - Performance

    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Performance")
            if viewModel.isLoadingCategories {
                HStack { Spacer(); ProgressView(); Spacer() }.padding()
            } else if let err = viewModel.categoriesError {
                Text(err).font(.caption).foregroundColor(.secondary).padding()
            } else if viewModel.categories.isEmpty {
                Text("No performance data available")
                    .font(.subheadline).foregroundColor(.secondary).padding()
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.categories, id: \.id) { category in
                        let instances = viewModel.cardStates.values
                            .filter { $0.instance.categoryId == category.id }
                            .sorted { $0.instance.key < $1.instance.key }
                        if !instances.isEmpty {
                            categoryGroup(category: category, instances: instances)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 24)
    }

    private func categoryGroup(category: PerformanceCategory, instances: [MetricCardState]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(category.name.uppercased())
                .font(.caption2).fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal).padding(.top, 10).padding(.bottom, 2)
            ForEach(instances, id: \.instance.key) { state in
                MetricCard(
                    state: Binding(
                        get: { viewModel.cardStates[state.instance.key] ?? state },
                        set: { viewModel.cardStates[state.instance.key] = $0 }
                    ),
                    onTap: {
                        Task { await viewModel.tapCard(instanceKey: state.instance.key) }
                    },
                    onTimeFrameChange: { tf in
                        Task { await viewModel.changeTimeFrame(tf, instanceKey: state.instance.key) }
                    }
                )
                Divider().padding(.leading)
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption).fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.horizontal)
            .padding(.bottom, 4)
    }

    private func statusColor(_ status: NetreoDevice.DeviceStatus) -> Color {
        switch status {
        case .up:          return .green
        case .down:        return .red
        case .warning:     return .orange
        case .critical:    return .red
        case .maintenance: return .blue
        case .unknown:     return .gray
        }
    }

    private func durationString(from start: Date) -> String {
        let s = max(0, Int(Date().timeIntervalSince(start)))
        let d = s / 86400; let h = (s % 86400) / 3600; let m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

// MARK: - MetricCard

private struct MetricCard: View {
    @Binding var state: MetricCardState
    let onTap: () -> Void
    let onTimeFrameChange: (TimeFrame) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Collapsed row — always visible
            HStack {
                statusDot
                Text(state.instance.title)
                    .font(.subheadline)
                Spacer()
                if state.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: state.isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .padding(.horizontal).padding(.vertical, 10)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }

            // Expanded content
            if state.isExpanded {
                VStack(spacing: 8) {
                    // Time frame picker
                    Picker("", selection: $state.selectedTimeFrame) {
                        ForEach(TimeFrame.allCases, id: \.self) { tf in
                            Text(tf.displayName).tag(tf)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .onChange(of: state.selectedTimeFrame) { newValue in
                        onTimeFrameChange(newValue)
                    }

                    if state.data.isEmpty {
                        Text(state.error != nil ? "Failed to load data" : "No data available")
                            .font(.caption).foregroundColor(.secondary).padding()
                    } else {
                        // Chart
                        Chart(state.data, id: \.timestamp) { point in
                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value(state.instance.unit, point.value)
                            )
                            .foregroundStyle(Color.accentColor)
                        }
                        .frame(height: 120)
                        .padding(.horizontal)

                        // Stat tiles
                        HStack(spacing: 0) {
                            statTile(label: "CURRENT", value: formatValue(state.current, unit: state.instance.unit))
                            Divider()
                            statTile(label: "AVG",     value: formatValue(state.average, unit: state.instance.unit))
                            Divider()
                            statTile(label: "MAX",     value: formatValue(state.max,     unit: state.instance.unit))
                        }
                        .frame(height: 56)
                        .padding(.horizontal)
                    }

                    if let err = state.error {
                        Text(err).font(.caption2).foregroundColor(.red).padding(.horizontal)
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private var statusDot: some View {
        let color: Color = {
            guard state.hasBeenFetched, let value = state.current else { return .gray }
            switch state.instance.unit {
            case "%":
                return value < 60 ? .green : value < 80 ? .orange : .red
            case "s":
                return value < 0.01 ? .green : value < 0.1 ? .orange : .red
            default:
                return .blue
            }
        }()
        return Circle().fill(color).frame(width: 8, height: 8)
    }

    private func statTile(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.subheadline).fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
    }

    private func formatValue(_ value: Double?, unit: String) -> String {
        guard let v = value else { return "—" }
        switch unit {
        case "s":
            if v < 0.001 { return "\(Int(v * 1_000_000)) µs" }
            if v < 1     { return String(format: "%.1f ms", v * 1000) }
            return String(format: "%.2f s", v)
        case "%":
            return String(format: "%.1f%%", v)
        case "B":
            let kb = v / 1024; let mb = kb / 1024; let gb = mb / 1024
            if gb >= 1 { return String(format: "%.1f GB", gb) }
            if mb >= 1 { return String(format: "%.1f MB", mb) }
            if kb >= 1 { return String(format: "%.0f kB", kb) }
            return String(format: "%.0f B", v)
        default:
            return String(format: "%.2f \(unit)", v)
        }
    }
}

// MARK: - StatusBadge

private struct StatusBadge: View {
    let status: NetreoDevice.DeviceStatus

    var body: some View {
        Text(status.rawValue.capitalized)
            .font(.caption2).fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color)
            .cornerRadius(5)
    }

    private var color: Color {
        switch status {
        case .up:          return Color(red: 0.13, green: 0.55, blue: 0.13)
        case .down:        return .red
        case .warning:     return .orange
        case .critical:    return .red
        case .maintenance: return .blue
        case .unknown:     return Color(.systemGray)
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
xcodebuild -scheme BeNeM -destination 'generic/platform=iOS' build 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Deploy and smoke-test**

```bash
./build_and_deploy.sh
```

Verify on device:
- Devices tab loads ≤20 devices immediately
- Settings → Devices section shows Stepper; changing it reloads the list
- Tap any device → DeviceDetailView opens
- "Performance" section shows a spinner while categories load
- After loading: category sub-headers (CPU, DISK, etc.) appear with collapsed metric cards
- Latency cards auto-expand and show a line chart with CURRENT / AVG / MAX tiles
- Tapping a collapsed card loads and expands it
- Tapping an expanded card collapses it
- Time frame picker changes the chart data
- "Current Issues" section still works as before

- [ ] **Step 4: Commit**

```bash
git add BeNeM/Views/DeviceDetailView.swift
git commit -m "feat: replace performance bars with on-demand MetricCard charts in DeviceDetailView"
```

---

## Notes

- **`fetchTimeSeries` stat group casing:** The BHNM API is case-sensitive for `metricFilterStatGroup`. The `statGroup` field on `PerformanceInstance` is set to `category.name` exactly as returned by `performance-category`. If charts come back empty, check the raw `category.name` value against what BHNM expects and adjust in `fetchPerformanceInstances` if needed.
- **Empty `dev_index`:** If `findDeviceIndex` returns `nil`, the performance section shows "Could not resolve device index". This can happen if the device name in the device list doesn't match what BHNM's `find` endpoint expects. The fallback is to try by IP: add `URLQueryItem(name: "ip", value: device.ip)` as a second attempt if needed.
- **Old `PerformanceMetric` struct and `fetchPerformanceMetrics` / `fetchRawMetricsResponse`:** These remain in `NetreoAPIService.swift` as dead code — leave them in place for now to avoid breaking any other callers that may not be visible in the files listed here.
