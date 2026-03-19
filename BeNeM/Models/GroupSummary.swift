import Foundation

/// Alarm level mapped to display colors (left → right in badge row).
enum HostAlarmStatus {
    case green   // ok / no active incidents
    case blue    // informational
    case yellow  // warning / minor
    case orange  // major
    case red     // critical / down
}

struct GroupSummary: Identifiable {
    let id: String
    let name: String
    let hostsGreen: Int    // up / ok
    let hostsBlue: Int     // informational
    let hostsYellow: Int   // warning / minor
    let hostsOrange: Int   // major
    let hostsRed: Int      // critical / down

    var totalHosts: Int { hostsGreen + hostsBlue + hostsYellow + hostsOrange + hostsRed }
    var hasDevices: Bool { totalHosts > 0 }
}
