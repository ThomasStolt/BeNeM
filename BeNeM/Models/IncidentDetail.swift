import Foundation

private func stripHTML(_ string: String) -> String {
    var result = string
    result = result.replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
    result = result.replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
    result = result.replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
    result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}

struct IncidentDetail {
    let incidentID: String
    let title: String
    let deviceName: String
    let deviceIP: String?
    let incidentState: String
    let primaryAlarmState: String
    let openTime: Date?
    let acknowledged: Bool
    let ackTime: Date?
    let ackUser: String?
    let ackComment: String?
    let alertType: String?
    let primaryAlarms: [PrimaryAlarm]
    let relatedAlarms: [PrimaryAlarm]
    let incidentLog: [LogEntry]

    struct PrimaryAlarm: Identifiable {
        let id = UUID()
        let state: String
        let type: String
        let name: String
        let output: String
        let time: Date?
    }

    struct LogEntry: Identifiable {
        let id = UUID()
        let state: String
        let time: Date?
        let username: String
        let comment: String
    }

    static func parse(from json: [String: Any]) -> IncidentDetail? {
        guard let incident = json["incident"] as? [String: Any] else { return nil }

        let fmt: (String?) -> Date? = { str in
            guard let s = str, !s.isEmpty else { return nil }
            // Try with explicit timezone first (e.g. "...+01:00" or "...Z")
            let isoWithTZ = ISO8601DateFormatter()
            isoWithTZ.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate,
                                       .withColonSeparatorInTime, .withTimeZone]
            if let d = isoWithTZ.date(from: s) { return d }
            // Fallback: no timezone in string — treat as server local time
            let isoLocal = ISO8601DateFormatter()
            isoLocal.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate,
                                      .withColonSeparatorInTime]
            isoLocal.timeZone = TimeZone.current
            return isoLocal.date(from: s)
        }

        let detail = incident["detail"] as? [String: Any]

        let primaryAlarms: [PrimaryAlarm] = (detail?["primary_alarm_log"] as? [[String: Any]] ?? []).map {
            PrimaryAlarm(
                state:  $0["state"]  as? String ?? "",
                type:   $0["type"]   as? String ?? "",
                name:   $0["name"]   as? String ?? "",
                output: stripHTML($0["output"] as? String ?? ""),
                time:   fmt($0["time"] as? String)
            )
        }

        let relatedAlarms: [PrimaryAlarm] = (detail?["relatedalarms"] as? [[String: Any]] ?? []).map {
            PrimaryAlarm(
                state:  $0["state"]  as? String ?? "",
                type:   $0["type"]   as? String ?? "",
                name:   $0["name"]   as? String ?? "",
                output: stripHTML($0["output"] as? String ?? ""),
                time:   fmt($0["time"] as? String)
            )
        }

        let logEntries: [LogEntry] = (detail?["incident_log"] as? [[String: Any]] ?? []).map {
            LogEntry(
                state:    $0["state"]    as? String ?? "",
                time:     fmt($0["time"] as? String),
                username: $0["username"] as? String ?? "",
                comment:  $0["comment"]  as? String ?? ""
            )
        }

        let ackRaw = incident["acknowledged"]
        let isAcked = (ackRaw as? Int == 1) || (ackRaw as? String == "1") || (ackRaw as? Bool == true)

        let deviceIP = incident["ip"] as? String
            ?? incident["device_ip"] as? String
            ?? incident["ip_address"] as? String
            ?? incident["ipaddress"] as? String
            ?? incident["host_ip"] as? String

        return IncidentDetail(
            incidentID:        incident["incident_id"]       as? String ?? "",
            title:             incident["title"]             as? String ?? "",
            deviceName:        incident["name"]              as? String ?? "",
            deviceIP:          deviceIP,
            incidentState:     incident["incident_state"]    as? String ?? "",
            primaryAlarmState: incident["primary_alarm_state"] as? String ?? "",
            openTime:          fmt(incident["incident_open_time"] as? String),
            acknowledged:      isAcked,
            ackTime:           fmt(incident["ack_time"] as? String),
            ackUser:           incident["ack_user"]          as? String,
            ackComment:        incident["ack_comment"]       as? String,
            alertType:         incident["alert_type"]        as? String,
            primaryAlarms:     primaryAlarms,
            relatedAlarms:     relatedAlarms,
            incidentLog:       logEntries
        )
    }
}
