# Device Detail View — Network Interfaces Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Network Interfaces section to `DeviceDetailView` showing interface names and speed/utilization fetched via the existing time-series metrics API.

**Architecture:** `DeviceDetailViewModel` gets three new published properties (`interfaceMetrics`, `isLoadingInterfaces`, `interfacesError`) and a new `loadInterfaces()` method that runs concurrently with the existing `loadIncidents()` and `loadPerformance()`. `DeviceDetailView` gets an `interfacesSection` inserted between the device header card and the current issues section, plus a `formatBps()` helper. No new files, no new API methods — both changes are additive to existing files.

**Tech Stack:** Swift 5.9, SwiftUI, async/await, `withTaskGroup` (already in use), form-urlencoded POST to BHNM REST API.

---

## File Map

| Action | File | Change |
|--------|------|--------|
| Modify | `BeNeM/ViewModels/DeviceDetailViewModel.swift` | Add `interfaceMetrics`, `isLoadingInterfaces`, `interfacesError`, `loadInterfaces()` |
| Modify | `BeNeM/Views/DeviceDetailView.swift` | Add `interfacesSection`, `formatBps()`, reorder VStack |

---

## Task 1: Add interface loading to `DeviceDetailViewModel`

**Files:**
- Modify: `BeNeM/ViewModels/DeviceDetailViewModel.swift`

- [ ] **Step 1: Add the three new published properties**

Open `BeNeM/ViewModels/DeviceDetailViewModel.swift`. After the `diskMetrics` property (line 8), add:

```swift
@Published var interfaceMetrics: [PerformanceMetric] = []
@Published var isLoadingInterfaces = true
@Published var interfacesError: String?
```

- [ ] **Step 2: Add `loadInterfaces()` to the task group in `load()`**

In `load()`, add a third task alongside the two existing ones:

```swift
func load() async {
    await withTaskGroup(of: Void.self) { group in
        group.addTask { await self.loadIncidents() }
        group.addTask { await self.loadPerformance() }
        group.addTask { await self.loadInterfaces() }
    }
}
```

- [ ] **Step 3: Implement `loadInterfaces()`**

Add this method after `loadPerformance()`:

```swift
@MainActor private func loadInterfaces() async {
    isLoadingInterfaces = true
    interfacesError = nil
    let name = device.name ?? device.ip
    do {
        let metrics = try await apiService.fetchPerformanceMetrics(
            deviceName: name, statGroup: "interface", units: "bps"
        )
        interfaceMetrics = deduplicated(metrics)
    } catch {
        interfacesError = error.localizedDescription
    }
    isLoadingInterfaces = false
}
```

Note: `deduplicated()` already exists in this file and handles deduplication by `instanceDescr`.

- [ ] **Step 4: Build to verify no compiler errors**

```bash
cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM
xcodebuild -scheme BeNeM -destination 'generic/platform=iOS' build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add BeNeM/ViewModels/DeviceDetailViewModel.swift
git commit -m "feat: add interface metrics loading to DeviceDetailViewModel"
```

---

## Task 2: Add interfaces section to `DeviceDetailView`

**Files:**
- Modify: `BeNeM/Views/DeviceDetailView.swift`

- [ ] **Step 1: Add `formatBps()` helper**

In `DeviceDetailView`, add this private method after the existing `formatBytes()` method (near the bottom of the file, around line 252):

```swift
private func formatBps(_ bps: Double) -> String {
    let kbps = bps / 1_000
    let mbps = kbps / 1_000
    let gbps = mbps / 1_000
    if gbps >= 1  { return String(format: "%.1f Gbps", gbps) }
    if mbps >= 1  { return String(format: "%.1f Mbps", mbps) }
    if kbps >= 1  { return String(format: "%.0f Kbps", kbps) }
    return String(format: "%.0f bps", bps)
}
```

Note: Uses SI (1,000-based) divisors — correct for network speeds, unlike `formatBytes()` which uses 1,024.

- [ ] **Step 2: Add `interfacesSection` computed property**

Add this computed property after `deviceHeaderCard(_:)` and before `issuesSection` (around line 55):

```swift
// MARK: - Network Interfaces

private var interfacesSection: some View {
    VStack(alignment: .leading, spacing: 0) {
        sectionHeader("Interfaces")
        if viewModel.isLoadingInterfaces {
            HStack { Spacer(); ProgressView(); Spacer() }.padding()
        } else if let err = viewModel.interfacesError {
            Text(err).font(.caption).foregroundColor(.secondary).padding()
        } else if viewModel.interfaceMetrics.isEmpty {
            Text("No interface data available")
                .font(.subheadline).foregroundColor(.secondary)
                .padding()
        } else {
            VStack(spacing: 0) {
                ForEach(viewModel.interfaceMetrics, id: \.instanceDescr) { metric in
                    HStack {
                        Text(metric.instanceDescr.isEmpty ? "—" : metric.instanceDescr)
                            .font(.subheadline)
                        Spacer()
                        Text(metric.value1.map { formatBps($0) } ?? "—")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal).padding(.vertical, 8)
                    Divider().padding(.leading)
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
        }
    }
    .padding(.top, 16)
}
```

- [ ] **Step 3: Insert `interfacesSection` in the view body**

In the `body` computed property, update the `VStack` to include `interfacesSection` between `deviceHeaderCard` and `issuesSection`:

```swift
VStack(alignment: .leading, spacing: 0) {
    deviceHeaderCard(device)
    interfacesSection
    issuesSection
    performanceSection
}
```

- [ ] **Step 4: Build to verify no compiler errors**

```bash
xcodebuild -scheme BeNeM -destination 'generic/platform=iOS' build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add BeNeM/Views/DeviceDetailView.swift
git commit -m "feat: add network interfaces section to DeviceDetailView"
```

---

## Task 3: Deploy and smoke-test

- [ ] **Step 1: Deploy to device**

```bash
./build_and_deploy.sh
```

- [ ] **Step 2: Smoke-test**

Open the app → Devices tab → tap any device → verify:
- Interfaces section appears between the header and Current Issues
- Section shows a spinner briefly, then either:
  - A list of interface rows with name + speed (e.g. `eth0  45.2 Mbps`)
  - "No interface data available"

- [ ] **Step 3: If interfaces show "No interface data available"**

The stat group name `"interface"` may not match what your BHNM instance uses. To diagnose, temporarily add a debug log in `loadInterfaces()` just before `interfaceMetrics = deduplicated(metrics)`:

```swift
// Temporary debug — remove after confirming stat group
#if DEBUG
print("[interfaces] raw count: \(metrics.count), first: \(metrics.first?.instanceDescr ?? "none")")
#endif
```

Then try alternative stat group names in `fetchPerformanceMetrics` call:
- `statGroup: "if_bandwidth"`
- `statGroup: "network"`
- `statGroup: "interface_traffic"`

Use the BHNM web UI (Monitoring → Devices → select device → Performance tab) to see which stat groups are populated. Remove the debug log once the correct stat group is found.

- [ ] **Step 4: Commit any stat group fix**

```bash
git add BeNeM/ViewModels/DeviceDetailViewModel.swift
git commit -m "fix: adjust interface stat group to match BHNM instance"
```
