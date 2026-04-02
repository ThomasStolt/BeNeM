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
