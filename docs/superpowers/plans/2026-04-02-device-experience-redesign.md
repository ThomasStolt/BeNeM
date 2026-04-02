# Device Experience Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the device data model, API layer, list view, and detail view for large-scale BHNM environments (4K–13K devices) using new 26.1.02 API features (UID, pagination, model/serial, interface details).

**Architecture:** Phase 1 replaces `NetreoDevice` with a new model using `UID` as the primary identifier, adds paginated fetch and server-side search to `NetreoAPIService`, and updates all consumers. Phase 2 rebuilds `DeviceListView` (paginated browse + search) and `DeviceDetailView` (type-aware header with icons, alarm bar, host info, current issues, context-dependent performance sections with pinned interfaces for network devices).

**Tech Stack:** Swift 5.9, SwiftUI, Swift Charts, async/await, BHNM RESTful API (26.1.02+)

---

## File Structure

### Phase 1 — Foundation

| Action | File | Responsibility |
|--------|------|---------------|
| Rewrite | `BeNeM/Models/NetreoDevice.swift` | Device model with UID-based identity, explicit typed fields, DeviceTypeClass enum |
| Modify | `BeNeM/Services/NetreoAPIService.swift` | New parsing, paginated fetch, search, category/site device lists |
| Modify | `BeNeM/ViewModels/DeviceListViewModel.swift` | Paginated browse + search state |
| Modify | `BeNeM/ViewModels/DeviceDetailViewModel.swift` | Update device property references |
| Modify | `BeNeM/Views/DeviceListView.swift` | Update references to new model properties |
| Modify | `BeNeM/Views/DeviceDetailView.swift` | Update references to new model properties |
| Modify | `BeNeM/Views/DashboardView.swift` | Update any device property references |

### Phase 2 — UI

| Action | File | Responsibility |
|--------|------|---------------|
| Rewrite | `BeNeM/Views/DeviceListView.swift` | Paginated browse, search bar, type-icon rows |
| Create | `BeNeM/Views/DeviceTypeIcon.swift` | Reusable device type icon (Linux/Windows/Router/Switch) drawn as SwiftUI shapes |
| Rewrite | `BeNeM/Views/DeviceDetailView.swift` | Header, alarm bar, host info, current issues, performance sections |
| Rewrite | `BeNeM/ViewModels/DeviceDetailViewModel.swift` | Type-aware loading: server metrics vs network interfaces, pinned interfaces |

---

## Task 1: Rewrite NetreoDevice Model

**Files:**
- Rewrite: `BeNeM/Models/NetreoDevice.swift`

- [ ] **Step 1: Replace NetreoDevice with new model**

Replace the entire contents of `BeNeM/Models/NetreoDevice.swift` with:

```swift
import Foundation

struct NetreoDevice: Identifiable, Hashable {
    let id: String           // UID (root_id) — primary identifier
    let uid: String          // same as id, explicit
    let guid: String         // globally unique: netreo-PIN-rootId
    let devIndex: String     // dev_index, used by some endpoints
    let name: String
    let ip: String
    let description: String
    let category: String
    let site: String
    let model: String?
    let serialNumber: String?
    let poll: Bool
    let monitor: Bool
    let snmpVersion: String?
    let createTime: String?
    let status: DeviceStatus

    enum DeviceStatus: String, CaseIterable {
        case up = "up"
        case down = "down"
        case warning = "warning"
        case critical = "critical"
        case unknown = "unknown"
        case maintenance = "maintenance"
    }

    /// Classifies device for icon selection based on description and category
    var typeClass: DeviceTypeClass {
        let desc = description.lowercased()
        let cat = category.lowercased()
        if desc.contains("linux") { return .linux }
        if desc.contains("windows") { return .windows }
        if desc.contains("router") || cat.contains("router") { return .router }
        if desc.contains("switch") || cat.contains("switch") { return .switchDevice }
        // Heuristics for common device descriptions
        if desc.contains("ubnt edgerouter") || desc.contains("draytek") { return .router }
        if desc.contains("edgeswitch") || desc.contains("catalyst") { return .switchDevice }
        return .unknown
    }
}

enum DeviceTypeClass: String, CaseIterable {
    case linux
    case windows
    case router
    case switchDevice
    case unknown

    /// Whether this device type shows server-style metrics (CPU/Memory/Disk)
    var isServer: Bool {
        switch self {
        case .linux, .windows: return true
        default: return false
        }
    }

    /// Whether this device type shows network-style metrics (interfaces/bandwidth)
    var isNetworkDevice: Bool {
        switch self {
        case .router, .switchDevice: return true
        default: return false
        }
    }
}
```

This drops `AnyCodable`, `DynamicCodingKeys`, `Codable` conformance, and the `additionalProperties` catch-all. The model is now a plain struct constructed by the API service's parsing logic. `Hashable` conformance is needed for `NavigationLink(value:)`.

- [ ] **Step 2: Verify the project builds**

Run:
```bash
cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM
xcodebuild -project BeNeM.xcodeproj -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20
```

Expected: Build FAILS — many files reference old properties (`device.hostname`, `device.deviceType`, `device.isActive`, `device.siteID`, `device.categoryID`, etc.). This is expected and will be fixed in the next tasks.

- [ ] **Step 3: Commit**

```bash
git add BeNeM/Models/NetreoDevice.swift
git commit -m "refactor: rewrite NetreoDevice model with UID-based identity

Replace IP-based identity with UID (root_id) from BHNM API. Add explicit
typed fields for model, serialNumber, guid, devIndex. Add DeviceTypeClass
enum for icon selection. Drop AnyCodable and additionalProperties."
```

---

## Task 2: Update NetreoAPIService Parsing

**Files:**
- Modify: `BeNeM/Services/NetreoAPIService.swift`

- [ ] **Step 1: Replace parseRESTfulDevice method**

In `NetreoAPIService.swift`, find the `parseRESTfulDevice(from:)` method (starts around line 337) and replace it entirely with:

```swift
    private func parseDevice(from dict: [String: Any]) -> NetreoDevice? {
        // UID is required — this is the primary identifier
        let uid: String
        if let u = dict["UID"] as? String { uid = u }
        else if let u = dict["UID"] as? Int { uid = String(u) }
        else { return nil }

        guard let ip = dict["ip"] as? String else { return nil }

        let guid = dict["GUID"] as? String ?? ""
        let devIndex = (dict["dev_index"] as? String) ?? (dict["dev_index"] as? Int).map(String.init) ?? ""
        let name = dict["name"] as? String ?? ip
        let description = dict["description"] as? String ?? ""
        let category = dict["category"] as? String ?? ""
        let site = dict["site"] as? String ?? ""
        let model = dict["model"] as? String
        let serialNumber = dict["serial_number"] as? String
        let poll = (dict["poll"] as? String) == "1"
        let monitor = (dict["monitor"] as? String) == "1"
        let snmpVersion = dict["snmp_version"] as? String
        let createTime = dict["create_time"] as? String

        let status: NetreoDevice.DeviceStatus = {
            if let color = (dict["alarm_color"] as? String)?.lowercased() {
                switch color {
                case "red":    return .critical
                case "orange": return .warning
                case "yellow": return .warning
                case "green":  return .up
                default: break
                }
            }
            if let colorInt = dict["alarm_color"] as? Int {
                switch colorInt {
                case 3:  return .critical
                case 2:  return .warning
                case 1:  return .warning
                case 0:  return .up
                default: break
                }
            }
            if let colorStr = dict["alarm_color"] as? String, let colorInt = Int(colorStr) {
                switch colorInt {
                case 3:  return .critical
                case 2:  return .warning
                case 1:  return .warning
                case 0:  return .up
                default: break
                }
            }
            if let s = (dict["status"] as? String)?.lowercased() {
                switch s {
                case "critical", "down": return .critical
                case "warning":          return .warning
                case "up", "ok":         return .up
                default: break
                }
            }
            if let upStatus = dict["up_status"] as? Int {
                return upStatus == 1 ? .up : .down
            }
            return (poll && monitor) ? .up : .unknown
        }()

        return NetreoDevice(
            id: uid, uid: uid, guid: guid, devIndex: devIndex,
            name: name, ip: ip, description: description,
            category: category, site: site,
            model: (model?.isEmpty == true) ? nil : model,
            serialNumber: (serialNumber?.isEmpty == true) ? nil : serialNumber,
            poll: poll, monitor: monitor,
            snmpVersion: snmpVersion, createTime: createTime,
            status: status
        )
    }
```

- [ ] **Step 2: Update all references from parseRESTfulDevice to parseDevice**

In `NetreoAPIService.swift`, find every call to `parseRESTfulDevice` and rename to `parseDevice`. There are two occurrences:

Line ~93 in `fetchDevices()`:
```swift
        return devicesArray.compactMap { parseDevice(from: $0) }
```

Line ~118 in `fetchDevicesPage()`:
```swift
        return devicesArray.compactMap { parseDevice(from: $0) }
```

- [ ] **Step 3: Update fetchDevices to return totalRecords**

Replace the `fetchDevices()` method with a version that returns total count:

```swift
    struct DevicePage {
        let devices: [NetreoDevice]
        let totalRecords: Int
    }

    func fetchDevices(recordStart: Int = 0, recordCount: Int = 50) async throws -> DevicePage {
        guard let url = URL(string: "\(configuration.baseURL)/fw/index.php?r=restful/devices/list") else {
            return DevicePage(devices: [], totalRecords: 0)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addProxyToken(&request)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [URLQueryItem(name: "password", value: configuration.apiKey)]
        if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
        params.append(URLQueryItem(name: "recordStart", value: String(recordStart)))
        params.append(URLQueryItem(name: "recordCount", value: String(recordCount)))
        request.httpBody = formEncodedBody(params)
        let (data, _) = try await urlSession.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return DevicePage(devices: [], totalRecords: 0)
        }
        let devicesArray: [[String: Any]]
        if let arr = json["devices"] as? [[String: Any]] {
            devicesArray = arr
        } else if let nested = json["data"] as? [String: Any],
                  let arr = nested["devices"] as? [[String: Any]] {
            devicesArray = arr
        } else {
            return DevicePage(devices: [], totalRecords: 0)
        }
        // totalRecords comes as String from API, displayRecords as Int
        let total: Int
        if let t = json["totalRecords"] as? Int { total = t }
        else if let t = json["totalRecords"] as? String, let n = Int(t) { total = n }
        else { total = devicesArray.count }

        #if DEBUG
        if let first = devicesArray.first {
            let debugLines = first.map { "\($0.key) = \($0.value)" }.sorted()
            UserDefaults.standard.set(debugLines.joined(separator: "\n"), forKey: "debug_device_fields")
        }
        #endif
        return DevicePage(devices: devicesArray.compactMap { parseDevice(from: $0) }, totalRecords: total)
    }
```

Remove the old `fetchDevicesPage(limit:offset:)` method — it's superseded.

- [ ] **Step 4: Add searchDevices method**

Add below `fetchDevices`:

```swift
    func searchDevices(query: String) async throws -> [NetreoDevice] {
        guard let url = URL(string: "\(configuration.baseURL)/fw/index.php?r=restful/devices/find") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addProxyToken(&request)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [
            URLQueryItem(name: "password", value: configuration.apiKey),
            URLQueryItem(name: "name", value: query),
        ]
        if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
        request.httpBody = formEncodedBody(params)
        let (data, _) = try await urlSession.data(for: request)
        // Response is a plain array, or a string error
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { parseDevice(from: $0) }
    }
```

- [ ] **Step 5: Add fetchDevicesForCategory and fetchDevicesForSite**

Add below `searchDevices`:

```swift
    func fetchDevicesForCategory(categoryId: String) async throws -> [NetreoDevice] {
        guard let url = URL(string: "\(configuration.baseURL)/fw/index.php?r=restful/category/device-list") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addProxyToken(&request)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [
            URLQueryItem(name: "password", value: configuration.apiKey),
            URLQueryItem(name: "id", value: categoryId),
        ]
        if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
        request.httpBody = formEncodedBody(params)
        let (data, _) = try await urlSession.data(for: request)
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { parseDevice(from: $0) }
    }

    func fetchDevicesForSite(siteId: String) async throws -> [NetreoDevice] {
        guard let url = URL(string: "\(configuration.baseURL)/fw/index.php?r=restful/site/device-list") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addProxyToken(&request)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [
            URLQueryItem(name: "password", value: configuration.apiKey),
            URLQueryItem(name: "id", value: siteId),
        ]
        if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
        request.httpBody = formEncodedBody(params)
        let (data, _) = try await urlSession.data(for: request)
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { parseDevice(from: $0) }
    }
```

- [ ] **Step 6: Update findDeviceIndex to use devIndex from find response**

The existing `findDeviceIndex` method returns `dev_index`. It still works correctly — it parses from the `/devices/find` response. No change needed, but verify it still compiles.

- [ ] **Step 7: Commit**

```bash
git add BeNeM/Services/NetreoAPIService.swift
git commit -m "refactor: update API service for new device model and pagination

Replace parseRESTfulDevice with parseDevice (UID-based). Add paginated
fetchDevices returning DevicePage with totalRecords. Add searchDevices
for server-side substring search. Add fetchDevicesForCategory and
fetchDevicesForSite for tactical drill-down."
```

---

## Task 3: Update All Consumers of NetreoDevice

**Files:**
- Modify: `BeNeM/ViewModels/DeviceListViewModel.swift`
- Modify: `BeNeM/ViewModels/DeviceDetailViewModel.swift`
- Modify: `BeNeM/Views/DeviceListView.swift`
- Modify: `BeNeM/Views/DeviceDetailView.swift`
- Modify: `BeNeM/Views/DashboardView.swift`

This task fixes all compile errors from the model change. The goal is a clean build — UI improvements come in Phase 2.

- [ ] **Step 1: Update DeviceListViewModel**

Replace the contents of `DeviceListViewModel.swift`:

```swift
import Foundation

@MainActor
class DeviceListViewModel: ObservableObject {
    @Published var devices: [NetreoDevice] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var totalRecords: Int = 0
    @Published var hasMore = false
    @Published var isLoadingMore = false

    // Search
    @Published var searchQuery: String = ""
    @Published var isSearching = false
    @Published var searchResults: [NetreoDevice] = []

    private var apiService: NetreoAPIService
    private let pageSize = 50

    var displayedDevices: [NetreoDevice] {
        searchQuery.count >= 2 ? searchResults : devices
    }

    init(apiService: NetreoAPIService) {
        self.apiService = apiService
    }

    func loadDevices() async {
        isLoading = true
        errorMessage = nil
        do {
            let page = try await apiService.fetchDevices(recordStart: 0, recordCount: pageSize)
            devices = page.devices
            totalRecords = page.totalRecords
            hasMore = page.devices.count < page.totalRecords
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadMoreDevices() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        do {
            let page = try await apiService.fetchDevices(recordStart: devices.count, recordCount: pageSize)
            devices.append(contentsOf: page.devices)
            hasMore = devices.count < page.totalRecords
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingMore = false
    }

    func search(query: String) async {
        guard query.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        do {
            searchResults = try await apiService.searchDevices(query: query)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSearching = false
    }

    func updateAPIService(_ newService: NetreoAPIService) {
        apiService = newService
        devices = []
        searchResults = []
        searchQuery = ""
        Task { await loadDevices() }
    }
}
```

This removes `addDevice`, `deleteDevice`, `renameDevice` (legacy operations not needed for the new device experience), replaces `fetchDevicesPage` with the new `fetchDevices`, and adds search support.

- [ ] **Step 2: Update DeviceDetailViewModel references**

In `DeviceDetailViewModel.swift`, update the `loadIncidents` method. The device properties have changed:
- `device.name` is now non-optional `String` (was `String?`)
- `device.ip` stays the same

Find:
```swift
            let deviceName = device.name ?? device.ip
```
Replace with:
```swift
            let deviceName = device.name
```

Also in `loadPerformanceStructure`, find:
```swift
        let name = device.name ?? device.ip
```
Replace with:
```swift
        let name = device.name
```

And in `tapCard`, find:
```swift
        let name = device.name ?? device.ip
```
Replace with:
```swift
        let name = device.name
```

- [ ] **Step 3: Update DeviceListView references**

In `DeviceListView.swift`, the key changes needed:
- Remove `showingAddDevice`, `AddDeviceView` sheet, and "Add" toolbar button (legacy)
- Remove `maxDevicesCount` AppStorage (replaced by internal pageSize)
- Update `loadDevices` calls (no more `limit:` parameter)
- Remove `onChange(of: maxDevicesCount)` handler

For now, do a minimal fix to get it compiling — Phase 2 will rewrite this file entirely. Replace `DeviceRowView`:

```swift
struct DeviceRowView: View {
    let device: NetreoDevice

    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading) {
                Text(device.name)
                    .font(.headline)
                HStack(spacing: 4) {
                    Text(device.ip)
                    Text("·").foregroundColor(.secondary)
                    Text(device.category)
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
            }

            Spacer()

            Text(device.status.rawValue.capitalized)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.2))
                .cornerRadius(8)
        }
        .padding(.vertical, 2)
    }

    private var statusColor: Color {
        switch device.status {
        case .up:          return .green
        case .down:        return .red
        case .warning:     return .orange
        case .critical:    return .red
        case .maintenance: return .blue
        case .unknown:     return .gray
        }
    }
}
```

Update the main `DeviceListView` body to remove legacy references. The key changes:
- Remove `showingAddDevice` state and `AddDeviceView` sheet
- Remove `maxDevicesCount` AppStorage
- Change `loadDevices(limit:)` calls to `loadDevices()`
- Remove `onChange(of: maxDevicesCount)` handler

- [ ] **Step 4: Update DeviceDetailView references**

In `DeviceDetailView.swift`, update references to old properties:
- `device.name ?? device.ip` → `device.name` (name is now non-optional)
- `device.deviceType` → `device.description` (for displaying type info)
- Remove reference to `device.deviceType` in `deviceIcon` — use `device.typeClass` instead

Update `deviceHeaderCard`:
```swift
    private func deviceHeaderCard(_ device: NetreoDevice) -> some View {
        HStack(spacing: 16) {
            Image(systemName: deviceIcon(for: device))
                .font(.system(size: 26))
                .foregroundColor(.accentColor)
                .frame(width: 52, height: 52)
                .background(Color(.tertiarySystemGroupedBackground))
                .cornerRadius(10)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.title3).fontWeight(.bold)
                Text(device.ip)
                    .font(.caption).foregroundColor(.secondary)
                if !device.description.isEmpty {
                    Text(device.description).font(.caption).foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            StatusBadge(status: device.status)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }
```

Update `deviceIcon` to use `typeClass`:
```swift
    private func deviceIcon(for device: NetreoDevice) -> String {
        switch device.typeClass {
        case .linux:        return "terminal"
        case .windows:      return "pc"
        case .router:       return "network"
        case .switchDevice: return "network"
        case .unknown:      return "desktopcomputer"
        }
    }
```

Update `.navigationTitle`:
```swift
        .navigationTitle(device.name)
```

- [ ] **Step 5: Update DashboardView if needed**

Check `DashboardView.swift` for any references to old device properties. The dashboard uses `DeviceListViewModel` — if it only accesses `viewModel.devices` for display counts or iteration, the changes from Step 1 should suffice. Fix any remaining compile errors related to `device.name` optionality or removed properties.

- [ ] **Step 6: Build and verify**

Run:
```bash
cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM
xcodebuild -project BeNeM.xcodeproj -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -30
```

Expected: BUILD SUCCEEDED. Fix any remaining compile errors before proceeding.

- [ ] **Step 7: Commit**

```bash
git add BeNeM/ViewModels/ BeNeM/Views/ 
git commit -m "refactor: update all consumers for new NetreoDevice model

Update DeviceListViewModel with pagination and search. Fix property
references across DeviceDetailViewModel, DeviceListView, DeviceDetailView,
and DashboardView for non-optional name, removed deviceType/hostname fields."
```

---

## Task 4: Build and Deploy to Device — Phase 1 Checkpoint

**Files:** None (verification only)

- [ ] **Step 1: Build and deploy**

```bash
cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM
./build_and_deploy.sh
```

Expected: App builds and deploys to TomiPhone13. Verify:
- Device list loads (may show fewer devices initially due to pagination)
- Tapping a device opens the detail view
- Device names, IPs, categories display correctly
- Performance data still loads

- [ ] **Step 2: Commit version bump if needed**

If build_and_deploy succeeds, Phase 1 foundation is complete.

---

## Task 5: Create DeviceTypeIcon View

**Files:**
- Create: `BeNeM/Views/DeviceTypeIcon.swift`

- [ ] **Step 1: Create the icon view**

Create `BeNeM/Views/DeviceTypeIcon.swift`:

```swift
import SwiftUI

struct DeviceTypeIcon: View {
    let typeClass: DeviceTypeClass
    var size: CGFloat = 60
    var color: Color = .green

    var body: some View {
        Group {
            switch typeClass {
            case .linux:
                linuxIcon
            case .windows:
                windowsIcon
            case .router:
                routerIcon
            case .switchDevice:
                switchIcon
            case .unknown:
                unknownIcon
            }
        }
        .frame(width: size, height: size)
    }

    // MARK: - Linux Penguin

    private var linuxIcon: some View {
        Image(systemName: "bird.fill")
            .resizable()
            .scaledToFit()
            .foregroundColor(color)
            .padding(size * 0.1)
    }

    // MARK: - Windows

    private var windowsIcon: some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height) * 0.7
            let origin = CGPoint(x: (canvasSize.width - s) / 2, y: (canvasSize.height - s) / 2)
            let gap: CGFloat = s * 0.06

            // Four panes of the Windows logo
            let halfW = (s - gap) / 2
            let halfH = (s - gap) / 2

            let panes = [
                CGRect(x: origin.x, y: origin.y, width: halfW, height: halfH),
                CGRect(x: origin.x + halfW + gap, y: origin.y, width: halfW, height: halfH),
                CGRect(x: origin.x, y: origin.y + halfH + gap, width: halfW, height: halfH),
                CGRect(x: origin.x + halfW + gap, y: origin.y + halfH + gap, width: halfW, height: halfH),
            ]
            for pane in panes {
                let path = RoundedRectangle(cornerRadius: 2).path(in: pane)
                context.fill(path, with: .color(color))
            }
        }
    }

    // MARK: - Router (arrows pointing out from center, rounded square background)

    private var routerIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18)
                .fill(color)
                .frame(width: size * 0.85, height: size * 0.85)

            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .resizable()
                .scaledToFit()
                .foregroundColor(Color(.systemBackground).opacity(0.85))
                .fontWeight(.bold)
                .frame(width: size * 0.5, height: size * 0.5)
        }
    }

    // MARK: - Switch (crossing arrows, circle background)

    private var switchIcon: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: size * 0.85, height: size * 0.85)

            Image(systemName: "arrow.triangle.swap")
                .resizable()
                .scaledToFit()
                .foregroundColor(Color(.systemBackground).opacity(0.85))
                .fontWeight(.bold)
                .frame(width: size * 0.45, height: size * 0.45)
        }
    }

    // MARK: - Unknown

    private var unknownIcon: some View {
        Image(systemName: "desktopcomputer")
            .resizable()
            .scaledToFit()
            .foregroundColor(color)
            .padding(size * 0.1)
    }
}
```

- [ ] **Step 2: Add file to Xcode project**

The file should be automatically picked up by Xcode since it's in the `BeNeM/Views/` directory. Verify by building.

- [ ] **Step 3: Build to verify**

```bash
xcodebuild -project BeNeM.xcodeproj -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add BeNeM/Views/DeviceTypeIcon.swift
git commit -m "feat: add DeviceTypeIcon view for Linux/Windows/Router/Switch"
```

---

## Task 6: Rebuild DeviceListView with Search

**Files:**
- Rewrite: `BeNeM/Views/DeviceListView.swift`

- [ ] **Step 1: Rewrite DeviceListView**

Replace the entire contents of `DeviceListView.swift`:

```swift
import SwiftUI

struct DeviceListView: View {
    @StateObject private var viewModel: DeviceListViewModel
    @State private var connectionStatus: ConnectionStatus = .unknown
    @AppStorage("refresh_interval") private var refreshInterval: Double = 120.0
    private let apiService: NetreoAPIService

    init(apiService: NetreoAPIService) {
        self.apiService = apiService
        _viewModel = StateObject(wrappedValue: DeviceListViewModel(apiService: apiService))
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(viewModel.displayedDevices) { device in
                    NavigationLink(destination: DeviceDetailView(device: device, apiService: apiService)) {
                        DeviceRowView(device: device)
                    }
                }

                if !viewModel.searchQuery.isEmpty && viewModel.searchQuery.count >= 2 {
                    // Search mode — no pagination
                    if viewModel.isSearching {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .listRowSeparator(.hidden)
                    } else if viewModel.searchResults.isEmpty {
                        Text("No devices found")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .listRowSeparator(.hidden)
                    }
                } else if viewModel.hasMore {
                    // Browse mode — load more
                    HStack {
                        Spacer()
                        if viewModel.isLoadingMore {
                            ProgressView()
                        } else {
                            Button("Load more") {
                                Task { await viewModel.loadMoreDevices() }
                            }
                        }
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                    .onAppear {
                        Task { await viewModel.loadMoreDevices() }
                    }
                }
            }
            .searchable(text: $viewModel.searchQuery, prompt: "Search devices...")
            .onChange(of: viewModel.searchQuery) { query in
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
                    guard viewModel.searchQuery == query else { return }
                    await viewModel.search(query: query)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    ConnectionBadgeButton(status: connectionStatus) {
                        Task { await viewModel.loadDevices() }
                    }
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image("BMCHelixLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)
                        if viewModel.totalRecords > 0 {
                            Text("Devices (\(viewModel.totalRecords))")
                                .font(.system(size: 18, weight: .bold))
                        } else {
                            Text("Devices")
                                .font(.system(size: 18, weight: .bold))
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    AutoRefreshButton(
                        interval: refreshInterval,
                        isLoading: viewModel.isLoading,
                        action: { await viewModel.loadDevices() }
                    )
                }
            }
            .refreshable { await viewModel.loadDevices() }
            .overlay {
                if viewModel.isLoading && viewModel.devices.isEmpty {
                    ProgressView("Loading devices...")
                }
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .onChange(of: viewModel.isLoading) { loading in
                guard !loading else { return }
                connectionStatus = viewModel.errorMessage == nil ? .connected : .disconnected
            }
        }
        .task {
            guard viewModel.devices.isEmpty && viewModel.errorMessage == nil else { return }
            await viewModel.loadDevices()
        }
        .onChange(of: ObjectIdentifier(apiService)) { _, _ in
            viewModel.updateAPIService(apiService)
        }
    }
}

struct DeviceRowView: View {
    let device: NetreoDevice

    var body: some View {
        HStack(spacing: 12) {
            DeviceTypeIcon(typeClass: device.typeClass, size: 36, color: statusColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.headline)
                HStack(spacing: 4) {
                    Text(device.ip)
                    Text("·")
                    Text(device.category)
                    Text("·")
                    Text(device.site)
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch device.status {
        case .up:          return .green
        case .down:        return .red
        case .warning:     return .orange
        case .critical:    return .red
        case .maintenance: return .blue
        case .unknown:     return .gray
        }
    }
}
```

- [ ] **Step 2: Build and verify**

```bash
xcodebuild -project BeNeM.xcodeproj -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add BeNeM/Views/DeviceListView.swift
git commit -m "feat: rebuild DeviceListView with pagination and search

Paginated device browsing with infinite scroll, server-side search via
/devices/find with 300ms debounce, device type icons in rows, total
device count in toolbar title."
```

---

## Task 7: Rebuild DeviceDetailView — Header, Alarms, Host Info

**Files:**
- Rewrite: `BeNeM/Views/DeviceDetailView.swift`

- [ ] **Step 1: Rewrite DeviceDetailView with new sections**

Replace the entire contents of `DeviceDetailView.swift`:

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
            VStack(spacing: 16) {
                headerSection(device)
                alarmBar
                hostInfoSection(device)
                issuesSection
                performanceSection
            }
            .padding(.bottom, 24)
        }
        .navigationTitle(device.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
    }

    // MARK: - Header

    private func headerSection(_ device: NetreoDevice) -> some View {
        VStack(spacing: 8) {
            DeviceTypeIcon(
                typeClass: device.typeClass,
                size: 80,
                color: statusColor(device.status)
            )

            Text(device.name)
                .font(.title2).fontWeight(.bold)
                .foregroundColor(.green)

            HStack(spacing: 6) {
                Label(device.description.isEmpty ? device.typeClass.rawValue : String(device.description.prefix(30)),
                      systemImage: "info.circle")
                Label(device.ip, systemImage: "network")
                Label(device.category, systemImage: "folder")
                Label(device.site, systemImage: "mappin")
            }
            .font(.caption2)
            .foregroundColor(.secondary)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    // MARK: - Alarm Summary Bar

    private var alarmBar: some View {
        HStack(spacing: 0) {
            alarmColumn(label: "HEALTHY", value: viewModel.healthyCount, color: .green)
            alarmColumn(label: "ACK", value: viewModel.ackCount, color: .blue)
            alarmColumn(label: "WARNING", value: viewModel.warningCount, color: .yellow)
            alarmColumn(label: "CRITICAL", value: viewModel.criticalCount, color: .red)
        }
        .padding(.horizontal)
    }

    private func alarmColumn(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title2).fontWeight(.bold)
                .foregroundColor(value > 0 ? color : Color(.systemGray4))
            Text(label)
                .font(.caption2)
                .foregroundColor(value > 0 ? color.opacity(0.8) : Color(.systemGray3))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Host Information (collapsible)

    private func hostInfoSection(_ device: NetreoDevice) -> some View {
        DisclosureGroup("HOST INFORMATION") {
            VStack(spacing: 0) {
                infoRow("Current State", value: device.status.rawValue.uppercased(),
                        valueColor: statusColor(device.status))
                infoRow("Type of Device", value: device.description)
                infoRow("Category", value: device.category)
                infoRow("Site", value: device.site)
                if let model = device.model {
                    infoRow("Model", value: model)
                }
                if let serial = device.serialNumber {
                    infoRow("Serial Number", value: serial)
                }
                if let snmp = device.snmpVersion {
                    infoRow("SNMP Version", value: snmp)
                }
                infoRow("UID", value: device.uid)
            }
        }
        .padding(.horizontal)
        .tint(.secondary)
    }

    private func infoRow(_ label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundColor(valueColor)
                .fontWeight(valueColor != .primary ? .semibold : .regular)
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }

    // MARK: - Current Issues

    private var issuesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("HOST CURRENT ISSUES")
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(.secondary)
                Spacer()
                if !viewModel.incidents.isEmpty {
                    Text("\(viewModel.incidents.count)")
                        .font(.caption2).fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.red)
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal)

            if viewModel.isLoadingIncidents {
                HStack { Spacer(); ProgressView(); Spacer() }.padding()
            } else if viewModel.incidents.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("No current issues")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                .padding()
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("TYPE").frame(width: 70, alignment: .leading)
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
                                .frame(width: 70, alignment: .leading)
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
                .cornerRadius(12)
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Performance

    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PERFORMANCE")
                .font(.caption).fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 4)

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
                        if !category.name.lowercased().contains("latency") {
                            let instances = viewModel.cardStates.values
                                .filter { $0.instance.categoryId == category.id }
                                .sorted { $0.instance.key < $1.instance.key }
                            if !instances.isEmpty {
                                categoryGroup(category: category, instances: instances)
                            }
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
                .padding(.horizontal)
            }
        }
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
                    }
                )
                Divider().padding(.leading)
            }
        }
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

    private func durationString(from start: Date) -> String {
        let s = max(0, Int(Date().timeIntervalSince(start)))
        let d = s / 86400; let h = (s % 86400) / 3600; let m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
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

// MARK: - MetricCard

private struct MetricCard: View {
    @Binding var state: MetricCardState
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
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

            if state.isExpanded {
                VStack(spacing: 8) {
                    if state.data.isEmpty {
                        Text(state.error != nil ? "Failed to load data" : "No data available")
                            .font(.caption).foregroundColor(.secondary).padding()
                    } else {
                        Chart(state.data, id: \.timestamp) { point in
                            AreaMark(
                                x: .value("Time", point.timestamp),
                                y: .value(state.instance.unit, point.value)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.catmullRom)
                            LineMark(
                                x: .value("Time", point.timestamp),
                                y: .value(state.instance.unit, point.value)
                            )
                            .foregroundStyle(Color.accentColor)
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis {
                            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                                    .foregroundStyle(Color.secondary.opacity(0.2))
                                AxisTick(stroke: StrokeStyle(lineWidth: 1))
                                    .foregroundStyle(Color.secondary.opacity(0.3))
                                AxisValueLabel()
                                    .foregroundStyle(Color.secondary)
                                    .font(.system(size: 10))
                            }
                        }
                        .frame(height: 120)
                        .padding(.leading, 4)
                        .padding(.trailing, 12)

                        HStack(spacing: 0) {
                            statTile(label: "CURRENT", value: formatValue(state.current, unit: state.instance.unit))
                            Divider()
                            statTile(label: "AVG", value: formatValue(state.average, unit: state.instance.unit))
                            Divider()
                            statTile(label: "MAX", value: formatValue(state.max, unit: state.instance.unit))
                        }
                        .frame(height: 56)
                        .padding(.horizontal)
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
            case "%":  return value < 60 ? .green : value < 80 ? .orange : .red
            case "s":  return value < 0.01 ? .green : value < 0.1 ? .orange : .red
            default:   return .blue
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
```

- [ ] **Step 2: Update DeviceDetailViewModel with alarm counts**

In `DeviceDetailViewModel.swift`, add alarm count properties after the existing `@Published` properties:

```swift
    @Published var healthyCount: Int = 0
    @Published var ackCount: Int = 0
    @Published var warningCount: Int = 0
    @Published var criticalCount: Int = 0
```

Update `loadIncidents()` to compute alarm counts from the filtered incidents:

After the line `incidents = all.filter { ... }`, add:

```swift
            // Compute alarm counts from incidents
            // NetreoIncident has .status (IncidentStatus) with .acknowledged case
            // and .severity (IncidentSeverity) with .critical, .warning, etc.
            var healthy = 0, ack = 0, warn = 0, crit = 0
            for incident in incidents {
                if incident.status == .acknowledged {
                    ack += 1
                } else {
                    switch incident.severity {
                    case .critical, .major: crit += 1
                    case .warning, .minor:  warn += 1
                    case .informational: break
                    }
                }
            }
            if incidents.isEmpty { healthy = 1 }
            healthyCount = healthy
            ackCount = ack
            warningCount = warn
            criticalCount = crit

- [ ] **Step 3: Build and verify**

```bash
xcodebuild -project BeNeM.xcodeproj -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add BeNeM/Views/DeviceDetailView.swift BeNeM/ViewModels/DeviceDetailViewModel.swift
git commit -m "feat: rebuild DeviceDetailView with header, alarms, host info, issues

Large device type icon, green device name, alarm summary bar (HEALTHY/
ACK/WARNING/CRITICAL), collapsible host info with model and serial
number, current issues with badge count, performance cards."
```

---

## Task 8: Add Pinned Interfaces Support

**Files:**
- Modify: `BeNeM/ViewModels/DeviceDetailViewModel.swift`
- Modify: `BeNeM/Views/DeviceDetailView.swift`

- [ ] **Step 1: Add pinned interfaces to DeviceDetailViewModel**

Add to `DeviceDetailViewModel`:

```swift
    // MARK: - Pinned Interfaces

    @Published var pinnedKeys: [String] = []

    private var pinnedDefaultsKey: String {
        "pinned_interfaces_\(device.uid)"
    }

    func loadPinnedInterfaces() {
        pinnedKeys = UserDefaults.standard.stringArray(forKey: pinnedDefaultsKey) ?? []
    }

    func pinInterface(key: String) {
        guard !pinnedKeys.contains(key) else { return }
        pinnedKeys.append(key)
        UserDefaults.standard.set(pinnedKeys, forKey: pinnedDefaultsKey)
    }

    func unpinInterface(key: String) {
        pinnedKeys.removeAll { $0 == key }
        UserDefaults.standard.set(pinnedKeys, forKey: pinnedDefaultsKey)
    }

    func isInterfacePinned(key: String) -> Bool {
        pinnedKeys.contains(key)
    }
```

In the `load()` method, add `loadPinnedInterfaces()`:

```swift
    func load() async {
        loadPinnedInterfaces()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadIncidents() }
            group.addTask { await self.loadPerformanceStructure() }
        }
    }
```

- [ ] **Step 2: Add pinned interfaces UI section to DeviceDetailView**

In `DeviceDetailView`, add a pinned interfaces section above the performance section. In the `body`, between `issuesSection` and `performanceSection`, add:

```swift
                if device.typeClass.isNetworkDevice {
                    pinnedInterfacesSection
                }
```

Add the section:

```swift
    // MARK: - Pinned Interfaces

    private var pinnedInterfacesSection: some View {
        let pinnedStates = viewModel.pinnedKeys.compactMap { key in
            viewModel.cardStates[key]
        }

        return Group {
            if !pinnedStates.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("PINNED INTERFACES")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom, 4)

                    VStack(spacing: 0) {
                        ForEach(pinnedStates, id: \.instance.key) { state in
                            HStack {
                                MetricCard(
                                    state: Binding(
                                        get: { viewModel.cardStates[state.instance.key] ?? state },
                                        set: { viewModel.cardStates[state.instance.key] = $0 }
                                    ),
                                    onTap: {
                                        Task { await viewModel.tapCard(instanceKey: state.instance.key) }
                                    }
                                )
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    viewModel.unpinInterface(key: state.instance.key)
                                } label: {
                                    Label("Unpin", systemImage: "pin.slash")
                                }
                            }
                            Divider().padding(.leading)
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
            }
        }
    }
```

In the `performanceSection`, for interface-type categories, add a pin button. In `categoryGroup`, wrap each `MetricCard` with a swipe action to pin:

After `MetricCard(...)` and before `Divider().padding(.leading)`, add:

```swift
                .swipeActions(edge: .leading) {
                    if viewModel.device.typeClass.isNetworkDevice {
                        Button {
                            if viewModel.isInterfacePinned(key: state.instance.key) {
                                viewModel.unpinInterface(key: state.instance.key)
                            } else {
                                viewModel.pinInterface(key: state.instance.key)
                            }
                        } label: {
                            Label(
                                viewModel.isInterfacePinned(key: state.instance.key) ? "Unpin" : "Pin",
                                systemImage: viewModel.isInterfacePinned(key: state.instance.key) ? "pin.slash" : "pin"
                            )
                        }
                        .tint(.orange)
                    }
                }
```

Note: Swipe actions only work on `List` rows, not on plain `VStack` items. If the performance section isn't using a `List`, we may need to use a context menu instead:

```swift
                .contextMenu {
                    if viewModel.device.typeClass.isNetworkDevice {
                        Button {
                            if viewModel.isInterfacePinned(key: state.instance.key) {
                                viewModel.unpinInterface(key: state.instance.key)
                            } else {
                                viewModel.pinInterface(key: state.instance.key)
                            }
                        } label: {
                            Label(
                                viewModel.isInterfacePinned(key: state.instance.key) ? "Unpin" : "Pin",
                                systemImage: viewModel.isInterfacePinned(key: state.instance.key) ? "pin.slash" : "pin"
                            )
                        }
                    }
                }
```

- [ ] **Step 3: Build and verify**

```bash
xcodebuild -project BeNeM.xcodeproj -scheme BeNeM -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add BeNeM/ViewModels/DeviceDetailViewModel.swift BeNeM/Views/DeviceDetailView.swift
git commit -m "feat: add pinned interfaces with UserDefaults persistence

Pin/unpin interfaces via context menu on network device detail view.
Pinned interfaces stored per device UID in UserDefaults. Pinned section
shown above performance for routers and switches."
```

---

## Task 9: Update CLAUDE.md with API Changes

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update the Used Endpoints table**

In `CLAUDE.md`, update the "Used Endpoints" table to include the new endpoints and parameters:

Add these rows:
```
| Device search        | POST | `/fw/index.php?r=restful/devices/find` (body: `name=<query>`) → substring match, returns array |
| Category devices     | POST | `/fw/index.php?r=restful/category/device-list` (body: `id=<categoryId>`) |
| Site devices         | POST | `/fw/index.php?r=restful/site/device-list` (body: `id=<siteId>`) |
```

Update the existing device list row to note pagination:
```
| Device list (paginated) | POST | `/fw/index.php?r=restful/devices/list` (body: `recordStart=<n>&recordCount=<n>`) → returns `{totalRecords, displayRecords, devices:[]}` |
```

- [ ] **Step 2: Update the Important Notes section**

Add a note about BHNM minimum version:
```
- **Minimum BHNM version:** 26.1.02. The app uses UID-based device identity, pagination, model/serial fields, and interface details — all require 26.1.01+.
```

Add a note about device identity:
```
- **Device identity** uses `UID` (root_id from BHNM) as the primary identifier, not IP. The `GUID` field provides globally unique cross-deployment identification.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with new API endpoints and device identity notes"
```

---

## Task 10: Final Build, Deploy, and Verify

**Files:** None (verification only)

- [ ] **Step 1: Full build and deploy**

```bash
cd /Users/thomasstolt/Library/CloudStorage/OneDrive-Persönlich/Documents/Github/BeNeM
./build_and_deploy.sh
```

- [ ] **Step 2: Verify on device**

Test the following on TomiPhone13:
1. Device list loads with paginated data and device type icons
2. Search bar appears and finds devices by partial name
3. "Load more" appears at bottom and loads next page
4. Total device count shows in toolbar title
5. Tapping a device shows the new detail view:
   - Large device type icon
   - Device name in green
   - Alarm summary bar (HEALTHY/ACK/WARNING/CRITICAL)
   - Collapsible Host Information with model and serial number
   - Current Issues section
   - Performance cards with charts
6. For network devices: long-press a metric card to pin/unpin
7. Navigate back and verify navigation works correctly

- [ ] **Step 3: Commit any fixes**

If any issues are found during testing, fix and commit before marking complete.
