# Device Detail View — Network Interfaces Section

**Date:** 2026-03-24
**Status:** Approved

## Goal

Add a **Network Interfaces** section to `DeviceDetailView` that lists the network interfaces of a device with their names and speed/utilization values.

## Design Decisions

- **Layout:** Interface name + formatted speed/utilization. No status dot (link state is not available from the time-series API without a dedicated interface-listing endpoint, and none is known to exist in this BHNM instance).
- **Data source:** Reuse the existing `fetchPerformanceMetrics` API call (`POST /fw/index.php?r=restful/devices/get-time-series-metrics`) with `statGroup: "interface"` (exact stat group name may require tuning against the live BHNM instance). No new API method needed.
- **Placement:** Interfaces section appears after the device header card and before the Current Issues section — it is topology information, not a problem report.
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
group.addTask { await self.loadInterfaces() }
```

`loadInterfaces()` calls:

```swift
apiService.fetchPerformanceMetrics(deviceName: name, statGroup: "interface", units: "bps")
```

The stat group string (`"interface"`) and units (`"bps"`) are the best-effort defaults. If the BHNM instance uses different stat group names, these must be adjusted after inspecting the raw API response.

### `DeviceDetailView` changes

Add `interfacesSection` computed property and insert it between `deviceHeaderCard` and `issuesSection` in the `VStack`.

Each row renders:
- `instanceDescr` — the interface name (e.g. `eth0`, `GigabitEthernet0/0`)
- `value1` formatted as bps/Kbps/Mbps/Gbps — speed or utilization average

If `interfaceMetrics` is empty after loading (no data for this stat group), the section shows "No interface data available" rather than being hidden, so users can tell the section exists but returned no data.

### `PerformanceMetric` reuse

No changes to `PerformanceMetric` or `fetchPerformanceMetrics`. The struct and method are general-purpose and already handle the `instanceDescr` + `value1`/`value2` shape returned by the time-series API.

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

## Notes

- The stat group name (`"interface"`) and units (`"bps"`) may need adjustment per BHNM instance. If the section shows "No interface data available" on a device known to have interfaces, log the raw JSON response from `fetchPerformanceMetrics` to discover the correct stat group and units values.
- `value1` is treated as the primary speed/utilization value. If the BHNM instance returns interface data in `value2` instead, `diskRow`-style logic (used/total) may be applicable, but this is out of scope for the initial implementation.
