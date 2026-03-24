# Device Detail View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `DeviceDetailView` that opens when tapping a device row, showing device info, active incidents for that device, and CPU/Memory/Disk performance metrics from the BHNM time-series API.

**Architecture:** Device header and metadata render immediately from the passed `NetreoDevice`. A `DeviceDetailViewModel` fetches incidents and performance metrics concurrently on appear; each section has its own loading state so the view is immediately useful. Performance is fetched via `POST /fw/index.php?r=restful/devices/get-time-series-metrics`.

**Tech Stack:** Swift 5.9, SwiftUI, async/await, `withTaskGroup` for concurrent fetches, form-urlencoded POST matching existing API patterns.

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `BeNeM/ViewModels/DeviceDetailViewModel.swift` | Fetch incidents + performance concurrently; expose published state |
| Create | `BeNeM/Views/DeviceDetailView.swift` | Scrollable detail: header card, current issues, performance bars |
| Modify | `BeNeM/Services/NetreoAPIService.swift` | Add `fetchPerformanceMetrics(deviceName:statGroup:units:)` |
| Modify | `BeNeM/Views/DeviceListView.swift` | Wrap `DeviceRowView` in `NavigationLink` |

---

## Task 1: Add `fetchPerformanceMetrics` to `NetreoAPIService`

**Files:**
- Modify: `BeNeM/Services/NetreoAPIService.swift`

Add a `PerformanceMetric` struct and a new method that calls the BHNM time-series API.

- [ ] **Step 1: Add `PerformanceMetric` struct near the top of `NetreoAPIService.swift`, after the class opening brace or as a file-level struct before the class**

```swift
struct PerformanceMetric {
    let instanceDescr: String
    let value1: Double?   // primary value (e.g. % used, bytes used)
    let value2: Double?   // secondary value where applicable (e.g. bytes total)
}
```

- [ ] **Step 2: Add `fetchPerformanceMetrics` method to `NetreoAPIService`**

Add this method after `fetchDevices()`:

```swift
func fetchPerformanceMetrics(
    deviceName: String,
    statGroup: String,
    units: String
) async throws -> [PerformanceMetric] {
    let urlString = "\(configuration.baseURL)/fw/index.php?r=restful/devices/get-time-series-metrics"
    guard let url = URL(string: urlString) else { return [] }

    var params = [
        URLQueryItem(name: "password",               value: configuration.apiKey),
        URLQueryItem(name: "metricFilterStatGroup",  value: statGroup),
        URLQueryItem(name: "metricFilterUnits",      value: units),
        URLQueryItem(name: "groupFilterBy",          value: "device"),
        URLQueryItem(name: "groupFilterValue",       value: deviceName),
        URLQueryItem(name: "timeFrameFilterBy",      value: "time_offset"),
        URLQueryItem(name: "timeFrameFilterValue",   value: "Last 24 Hours"),
        URLQueryItem(name: "returnFormatFilterBy",   value: "average"),
    ]
    if let pin = configuration.pin {
        params.append(URLQueryItem(name: "pin", value: pin))
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = formEncodedBody(params)

    let (data, _) = try await urlSession.data(for: request)
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let metrics = json["metrics"] as? [[String: Any]] else { return [] }

    return metrics.compactMap { dict -> PerformanceMetric? in
        let descr = dict["instanceDescr"] as? String ?? ""
        let v1 = (dict["value1"] as? String).flatMap(Double.init)
               ?? dict["value1"] as? Double
        let v2 = (dict["value2"] as? String).flatMap(Double.init)
               ?? dict["value2"] as? Double
        return PerformanceMetric(instanceDescr: descr, value1: v1, value2: v2)
    }
}
```

- [ ] **Step 3: Build to verify no compiler errors**

```bash
cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM
xcodebuild -scheme BeNeM -destination 'generic/platform=iOS' build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add BeNeM/Services/NetreoAPIService.swift
git commit -m "feat: add fetchPerformanceMetrics to NetreoAPIService"
```

---

## Task 2: Create `DeviceDetailViewModel`

**Files:**
- Create: `BeNeM/ViewModels/DeviceDetailViewModel.swift`

- [ ] **Step 1: Create the file**

```swift
import Foundation

@MainActor
class DeviceDetailViewModel: ObservableObject {
    @Published var incidents: [NetreoIncident] = []
    @Published var cpuMetrics: [PerformanceMetric] = []
    @Published var memoryMetrics: [PerformanceMetric] = []
    @Published var diskMetrics: [PerformanceMetric] = []
    @Published var isLoadingIncidents = true
    @Published var isLoadingPerformance = true
    @Published var incidentsError: String?
    @Published var performanceError: String?

    private let apiService: NetreoAPIService
    let device: NetreoDevice

    init(device: NetreoDevice, apiService: NetreoAPIService) {
        self.device = device
        self.apiService = apiService
    }

    func load() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadIncidents() }
            group.addTask { await self.loadPerformance() }
        }
    }

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
                    || incName.lowercased().hasPrefix(deviceName.lowercased().components(separatedBy: ".").first ?? deviceName.lowercased())
            }
        } catch {
            incidentsError = error.localizedDescription
        }
        isLoadingIncidents = false
    }

    private func loadPerformance() async {
        isLoadingPerformance = true
        performanceError = nil
        let name = device.name ?? device.ip
        do {
            async let cpu  = apiService.fetchPerformanceMetrics(deviceName: name, statGroup: "cpu",    units: "%")
            async let mem  = apiService.fetchPerformanceMetrics(deviceName: name, statGroup: "memory", units: "%")
            async let disk = apiService.fetchPerformanceMetrics(deviceName: name, statGroup: "disk",   units: "%")
            let (c, m, d) = try await (cpu, mem, disk)
            cpuMetrics    = c
            memoryMetrics = m
            diskMetrics   = d
        } catch {
            performanceError = error.localizedDescription
        }
        isLoadingPerformance = false
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -scheme BeNeM -destination 'generic/platform=iOS' build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add BeNeM/ViewModels/DeviceDetailViewModel.swift
git commit -m "feat: add DeviceDetailViewModel with concurrent incident + performance loading"
```

---

## Task 3: Create `DeviceDetailView`

**Files:**
- Create: `BeNeM/Views/DeviceDetailView.swift`

The view has three visual sections:
1. **Device Header** — status dot, name, IP · deviceType · site
2. **Current Issues** — table rows showing type / description / duration per incident
3. **Performance** — CPU bar, Memory bar, Disk bars per mount point

- [ ] **Step 1: Create the file**

```swift
import SwiftUI

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
                    // Column headers
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
            if viewModel.isLoadingPerformance {
                HStack { Spacer(); ProgressView(); Spacer() }.padding()
            } else if let err = viewModel.performanceError {
                Text(err).font(.caption).foregroundColor(.secondary).padding()
            } else {
                VStack(spacing: 12) {
                    if let cpu = viewModel.cpuMetrics.first {
                        metricRow(label: "CPU", metric: cpu, color: .blue)
                    }
                    if let mem = viewModel.memoryMetrics.first {
                        metricRow(label: "Memory", metric: mem, color: .green)
                    }
                    if !viewModel.diskMetrics.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Disk")
                                .font(.subheadline).fontWeight(.medium)
                                .padding(.horizontal)
                            ForEach(viewModel.diskMetrics, id: \.instanceDescr) { m in
                                diskRow(metric: m)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
                .background(Color(.secondarySystemGroupedBackground))
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 24)
    }

    // MARK: - Sub-Views

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption).fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.horizontal)
            .padding(.bottom, 4)
    }

    private func metricRow(label: String, metric: PerformanceMetric, color: Color) -> some View {
        let pct = metric.value1 ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline).fontWeight(.medium)
                Spacer()
                Text(String(format: "%.1f%%", pct))
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(barColor(pct: pct))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor(pct: pct))
                        .frame(width: geo.size.width * CGFloat(min(pct, 100) / 100), height: 8)
                }
            }
            .frame(height: 8)
        }
        .padding(.horizontal)
    }

    private func diskRow(metric: PerformanceMetric) -> some View {
        // value1 = used bytes, value2 = total bytes (if available); otherwise treat value1 as %
        let (usedPct, label): (Double, String) = {
            if let v1 = metric.value1, let v2 = metric.value2, v2 > 0 {
                let pct = (v1 / v2) * 100
                let usedStr  = formatBytes(v1)
                let totalStr = formatBytes(v2)
                return (pct, "\(usedStr) of \(totalStr)")
            } else if let v1 = metric.value1 {
                return (v1, String(format: "%.1f%% used", v1))
            }
            return (0, "—")
        }()

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(metric.instanceDescr.isEmpty ? "disk" : metric.instanceDescr)
                    .font(.caption).foregroundColor(.secondary)
                Spacer()
                Text(label).font(.caption2).foregroundColor(.secondary)
                Text(String(format: "%.0f%%", usedPct))
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(barColor(pct: usedPct))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(.systemGray5))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor(pct: usedPct))
                        .frame(width: geo.size.width * CGFloat(min(usedPct, 100) / 100), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(.horizontal)
    }

    // MARK: - Helpers

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

    private func barColor(pct: Double) -> Color {
        switch pct {
        case ..<60: return .green
        case ..<80: return .orange
        default:    return .red
        }
    }

    private func durationString(from start: Date) -> String {
        let s = max(0, Int(Date().timeIntervalSince(start)))
        let d = s / 86400; let h = (s % 86400) / 3600; let m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    private func formatBytes(_ bytes: Double) -> String {
        let kb = bytes / 1024; let mb = kb / 1024; let gb = mb / 1024
        if gb >= 1  { return String(format: "%.1f GB", gb) }
        if mb >= 1  { return String(format: "%.1f MB", mb) }
        if kb >= 1  { return String(format: "%.0f kB", kb) }
        return String(format: "%.0f B", bytes)
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

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -scheme BeNeM -destination 'generic/platform=iOS' build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add BeNeM/Views/DeviceDetailView.swift
git commit -m "feat: add DeviceDetailView with header, issues, and performance sections"
```

---

## Task 4: Wire navigation in `DeviceListView`

**Files:**
- Modify: `BeNeM/Views/DeviceListView.swift`

- [ ] **Step 1: Add `apiService` property and wrap `DeviceRowView` in `NavigationLink`**

`DeviceListView` already has `viewModel` which has `apiService` as a private property. Expose it by passing `apiService` through to the link, or store it directly in the view. The simplest approach: store `apiService` as a property on the view itself (it already receives it in `init`).

Change the `init` to also store `apiService`:

```swift
// Add property:
private let apiService: NetreoAPIService

// Update init:
init(apiService: NetreoAPIService) {
    self.apiService = apiService
    _viewModel = StateObject(wrappedValue: DeviceListViewModel(apiService: apiService))
}
```

Then wrap the row in the ForEach:

```swift
ForEach(viewModel.devices) { device in
    NavigationLink(destination: DeviceDetailView(device: device, apiService: apiService)) {
        DeviceRowView(device: device)
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
xcodebuild -scheme BeNeM -destination 'generic/platform=iOS' build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Deploy and smoke-test**

```bash
./build_and_deploy.sh
```

Verify:
- Tapping a device row opens `DeviceDetailView`
- Device name, IP, status badge show immediately
- Incidents section shows a spinner then loads (or "No active issues")
- Performance section shows a spinner then loads bars for CPU/Memory/Disk
- If bars show empty (0%), check what `metricFilterStatGroup`/`metricFilterUnits` values BHNM returns by logging the raw API response and adjusting the values in `DeviceDetailViewModel.loadPerformance()`

- [ ] **Step 4: Commit**

```bash
git add BeNeM/Views/DeviceListView.swift
git commit -m "feat: navigate to DeviceDetailView on device row tap"
```

---

## Notes

- **Performance stat groups:** The plan uses `statGroup: "cpu"/"memory"/"disk"` with `units: "%"`. These are the most common BHNM values but may need adjustment. If metrics come back empty, log the raw JSON from `fetchPerformanceMetrics` and adjust the stat group / units strings to match what your BHNM instance reports.
- **Disk value interpretation:** The plan attempts both "bytes used/total" (value1/value2) and "percentage" (value1 alone). BHNM instances vary — adjust `diskRow()` based on actual API response.
- **Incident matching:** The filter in `loadIncidents()` uses case-insensitive name match + base hostname prefix as fallback, consistent with how `TacticalViewModel` does device–incident matching.
