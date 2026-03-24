# Device Detail View — Network Interfaces Section

**Date:** 2026-03-24
**Status:** Approved

## Goal

Add a **Network Interfaces** section to `DeviceDetailView` that lists the network interfaces of a device with their names and speed/utilization values.

## Design Decisions

- **Layout:** Interface name + formatted speed/utilization. No status dot (link state is not available from the time-series API without a dedicated interface-listing endpoint, and none is known to exist in this BHNM instance).
- **Data source:** Reuse the existing `fetchPerformanceMetrics` API call (`POST /fw/index.php?r=restful/devices/get-time-series-metrics`) with `statGroup: "interface"` (exact stat group name may require tuning against the live BHNM instance). No new API method needed.
- **Placement:** Interfaces section is inserted between the device header card and the Current Issues section. This changes the existing section order from `header → issues → performance` to `header → interfaces → issues → performance`.
- **Loading:** Concurrent with incidents and performance via `withTaskGroup`, following the existing pattern in `DeviceDetailViewModel`.

## Architecture

### `DeviceDetailViewModel` changes

Add three new published properties alongside the existing performance state:

```swift
@Published var interfaceMetrics: [PerformanceMetric] = []
@Published var isLoadingInterfaces = true
@Published var interfacesError: String?
```

Add `loadInterfaces()` as a concurrent task in `load()`:

```swift
func load() async {
    await withTaskGroup(of: Void.self) { group in
        group.addTask { await self.loadIncidents() }
        group.addTask { await self.loadPerformance() }
        group.addTask { await self.loadInterfaces() }   // new
    }
}
```

`loadInterfaces()` follows the exact same pattern as `loadPerformance()` — set loading flag, clear error, try/catch, apply `deduplicated()`, set loading flag false at end:

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

The existing `deduplicated()` helper on `DeviceDetailViewModel` (already used for cpu/memory/disk) is applied to `interfaceMetrics` to prevent duplicate `instanceDescr` rows.

### `DeviceDetailView` changes

**Section order change:** Insert `interfacesSection` between `deviceHeaderCard` and `issuesSection`:

```swift
VStack(alignment: .leading, spacing: 0) {
    deviceHeaderCard(device)
    interfacesSection      // new — was: issuesSection first
    issuesSection
    performanceSection
}
```

Add `interfacesSection` computed property following the same loading/error/empty/data pattern used by `issuesSection` and `performanceSection`:

- While `isLoadingInterfaces == true`: show `ProgressView`
- If `interfacesError != nil`: show error text
- If `isLoadingInterfaces == false && interfaceMetrics.isEmpty`: show "No interface data available" (the `isLoadingInterfaces == false` guard is required — the empty state must not appear while loading)
- Otherwise: render one row per `PerformanceMetric` in `interfaceMetrics`

Each row:
- Left: `metric.instanceDescr` (interface name, e.g. `eth0`, `GigabitEthernet0/0`)
- Right: `metric.value1` formatted via a new `formatBps()` helper

### `formatBps()` helper

Add a private helper to `DeviceDetailView` alongside `formatBytes()`:

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

If `value1` is nil, display `"—"` instead.

## Data Flow

```
DeviceDetailView.task
  └─ DeviceDetailViewModel.load()
       └─ withTaskGroup
            ├─ loadIncidents()
            ├─ loadPerformance()   (cpu / memory / disk)
            └─ loadInterfaces()   ← new
                  └─ fetchPerformanceMetrics(statGroup: "interface", units: "bps")
                        └─ POST /fw/index.php?r=restful/devices/get-time-series-metrics
```

## Error Handling

Follows the existing pattern: errors are caught, stored in `interfacesError`, and shown inline in the section. Loading failures do not affect other sections.

## Files Changed

| Action | File | Change |
|--------|------|--------|
| Modify | `BeNeM/ViewModels/DeviceDetailViewModel.swift` | Add `interfaceMetrics`, `isLoadingInterfaces`, `interfacesError`, `loadInterfaces()` |
| Modify | `BeNeM/Views/DeviceDetailView.swift` | Add `interfacesSection`, `formatBps()`, update section order in body |

## Notes

- The stat group name (`"interface"`) and units (`"bps"`) may need adjustment per BHNM instance. If the section shows "No interface data available" on a device known to have interfaces, log the raw JSON response from `fetchPerformanceMetrics` to discover the correct stat group and units values.
- `value1` is treated as the primary speed/utilization value. If the BHNM instance returns data in `value2` instead, adjust accordingly after inspecting the API response.
- No changes are needed to `PerformanceMetric` or `fetchPerformanceMetrics` — both are already general-purpose.
