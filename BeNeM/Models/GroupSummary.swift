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
    // H — Hosts (all active polled devices, green = no host incident)
    let hostsGreen: Int
    let hostsBlue: Int
    let hostsYellow: Int
    let hostsOrange: Int
    let hostsRed: Int
    // S — Services (only devices with service-check incidents)
    let servicesGreen: Int
    let servicesBlue: Int
    let servicesYellow: Int
    let servicesOrange: Int
    let servicesRed: Int
    // T — Thresholds (only devices with threshold incidents)
    let thresholdsGreen: Int
    let thresholdsBlue: Int
    let thresholdsYellow: Int
    let thresholdsOrange: Int
    let thresholdsRed: Int
    // A — Anomalies (ML-based deviation detections, distinct from threshold alarms)
    let anomaliesGreen: Int
    let anomaliesBlue: Int
    let anomaliesYellow: Int
    let anomaliesOrange: Int
    let anomaliesRed: Int

    var totalHosts: Int { hostsGreen + hostsBlue + hostsYellow + hostsOrange + hostsRed }
    var totalAnomalies: Int { anomaliesGreen + anomaliesBlue + anomaliesYellow + anomaliesOrange + anomaliesRed }
    var hasDevices: Bool { totalHosts > 0 }

    /// True if any H/S/T metric has a non-green (alarm) value.
    var hasAlarms: Bool {
        hostsBlue + hostsYellow + hostsOrange + hostsRed > 0 ||
        servicesBlue + servicesYellow + servicesOrange + servicesRed > 0 ||
        thresholdsBlue + thresholdsYellow + thresholdsOrange + thresholdsRed > 0
    }
}
