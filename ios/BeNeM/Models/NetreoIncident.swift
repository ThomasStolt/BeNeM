import Foundation
import SwiftUI

struct NetreoIncident: Codable, Identifiable, Hashable {
    var id: String { incidentID }

    /// Short display ID: strips any prefix up to the last "-", then prepends "#".
    /// e.g. "#NetreoCloudDemo-58431" → "#58431", "58431" → "#58431"
    var displayID: String {
        let bare = incidentID.hasPrefix("#") ? String(incidentID.dropFirst()) : incidentID
        if let dash = bare.lastIndex(of: "-") {
            return "#" + bare[bare.index(after: dash)...]
        }
        return "#\(bare)"
    }
    let incidentID: String
    let deviceIP: String?
    let deviceName: String?
    let summary: String
    let description: String?
    let severity: IncidentSeverity
    /// BHNM's own state. **Never carries the ack flag** — see `IncidentState`.
    var state: IncidentState
    /// The ack flag. Meaningful on any state; the pills only read it inside OPEN.
    var acknowledged: Bool
    /// Who acknowledged, per BHNM. Feeds search.
    let ackUser: String?
    /// When the middleware recorded the close. Present only on CLOSED.
    let closedAt: Date?
    /// The raw `incident_state` exactly as served, `ACKNOWLEDGED` and all.
    /// Retained until the middleware's M1-drop. **Do not filter on it** — use `state`.
    let incidentState: String
    let category: String?
    let startTime: Date
    let acknowledgedTime: Date?
    let resolvedTime: Date?
    let acknowledgedBy: String?
    
    enum IncidentSeverity: String, Codable, CaseIterable {
        case critical = "critical"
        case major = "major"
        case minor = "minor"
        case warning = "warning"
        case informational = "informational"
        
        var color: Color {
            switch self {
            case .critical:
                return .red
            case .major:
                return .orange
            case .minor:
                return .yellow
            case .warning:
                return .yellow
            case .informational:
                return .blue
            }
        }
        
        var priority: Int {
            switch self {
            case .critical:
                return 5
            case .major:
                return 4
            case .minor:
                return 3
            case .warning:
                return 2
            case .informational:
                return 1
            }
        }
    }
    
    enum IncidentStatus: String, Codable, CaseIterable {
        case active = "active"
        case acknowledged = "acknowledged"
        case resolved = "resolved"
        case closed = "closed"
    }

    /// **BHNM has three incident states, and acknowledged is not one of them.**
    ///
    /// Acknowledged is a FLAG on an OPEN incident. With one field, an
    /// acknowledged incident whose alarms then clear can only be shown as one
    /// or the other — which is the whole reason middleware 2.20.0 split them.
    enum IncidentState: String, Codable, CaseIterable {
        case open = "OPEN"
        case alarmsCleared = "ALARMS CLEARED"
        case closed = "CLOSED"

        /// An unrecognised value becomes `.open` rather than passing through.
        /// TOTL is OPEN + CLRD + CLSD, so a state in none of the three would
        /// drop the incident out of EVERY pill and vanish it from the list.
        /// Loud beats gone — and this mirrors the middleware's own `state_of()`
        /// exactly, so the two ends cannot disagree about an unknown value.
        init(bhnm raw: String?) {
            self = IncidentState(rawValue: (raw ?? "").trimmingCharacters(in: .whitespaces).uppercased()) ?? .open
        }
    }

    /// **DERIVED, never stored.** Rows, the detail screen and the pills all read
    /// this, so making it a view of `state` + `acknowledged` is what stops the
    /// three disagreeing. Before 2.14.0 it was a stored field parsed in parallel
    /// with `incidentState`, and the two could — and did — say different things.
    var status: IncidentStatus {
        if state == .closed { return .closed }
        return acknowledged ? .acknowledged : .active
    }

    enum CodingKeys: String, CodingKey {
        case incidentID = "incident_id"
        case deviceIP = "device_ip"
        case deviceName = "device_name"
        case summary
        case description
        case severity
        case status
        case state
        case acknowledged
        case ackUser = "ack_user"
        case closedAt = "closed_at"
        case incidentState = "incident_state"
        case category
        case startTime = "start_time"
        case acknowledgedTime = "acknowledged_time"
        case resolvedTime = "resolved_time"
        case acknowledgedBy = "acknowledged_by"
    }
    
    /// One initialiser, taking the two facts. There is deliberately no
    /// `status:` overload — a second way in is a second thing that can disagree.
    init(incidentID: String, deviceIP: String?, deviceName: String?, summary: String,
         description: String?, severity: IncidentSeverity,
         state: IncidentState = .open, acknowledged: Bool = false,
         ackUser: String? = nil, closedAt: Date? = nil,
         incidentState: String = "OPEN", category: String?, startTime: Date,
         acknowledgedTime: Date? = nil, resolvedTime: Date? = nil, acknowledgedBy: String? = nil) {
        self.incidentID = incidentID
        self.deviceIP = deviceIP
        self.deviceName = deviceName
        self.summary = summary
        self.description = description
        self.severity = severity
        self.state = state
        self.acknowledged = acknowledged
        self.ackUser = ackUser
        self.closedAt = closedAt
        self.incidentState = incidentState
        self.category = category
        self.startTime = startTime
        self.acknowledgedTime = acknowledgedTime
        self.resolvedTime = resolvedTime
        self.acknowledgedBy = acknowledgedBy
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        incidentID = try container.decode(String.self, forKey: .incidentID)
        deviceIP = try container.decodeIfPresent(String.self, forKey: .deviceIP)
        deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName)
        summary = try container.decode(String.self, forKey: .summary)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        
        if let severityString = try? container.decode(String.self, forKey: .severity) {
            severity = IncidentSeverity(rawValue: severityString.lowercased()) ?? .informational
        } else {
            severity = .informational
        }
        
        incidentState = (try? container.decodeIfPresent(String.self, forKey: .incidentState)) ?? "OPEN"

        // Read the NEW fields, and fall back to `incident_state` ONLY when
        // `state` is absent — a middleware older than 2.20.0, or the legacy
        // getincidents fall-through. The fallback maps ACKNOWLEDGED onto
        // state OPEN + flag true, which is the same mapping IncidentState(bhnm:)
        // makes. Deleted at M1-drop. `decodeIfPresent` throughout: a client that
        // REQUIRES a key cannot be deployed ahead of the server that sends it.
        let servedState = try? container.decodeIfPresent(String.self, forKey: .state)
        if let servedState {
            state = IncidentState(bhnm: servedState)
        } else {
            state = IncidentState(bhnm: incidentState)
        }
        if let flag = try? container.decodeIfPresent(Bool.self, forKey: .acknowledged) {
            acknowledged = flag
        } else if let flag = try? container.decodeIfPresent(Int.self, forKey: .acknowledged) {
            acknowledged = flag != 0
        } else {
            acknowledged = incidentState.uppercased() == "ACKNOWLEDGED"
        }
        ackUser = try? container.decodeIfPresent(String.self, forKey: .ackUser)
        if let epoch = try? container.decodeIfPresent(Double.self, forKey: .closedAt) {
            closedAt = Date(timeIntervalSince1970: epoch)
        } else {
            closedAt = nil
        }
        category = try container.decodeIfPresent(String.self, forKey: .category)
        
        if let timestamp = try? container.decode(Double.self, forKey: .startTime) {
            startTime = Date(timeIntervalSince1970: timestamp)
        } else if let dateString = try? container.decode(String.self, forKey: .startTime) {
            let formatter = ISO8601DateFormatter()
            startTime = formatter.date(from: dateString) ?? Date()
        } else {
            startTime = Date()
        }
        
        if let timestamp = try? container.decode(Double.self, forKey: .acknowledgedTime) {
            acknowledgedTime = Date(timeIntervalSince1970: timestamp)
        } else if let dateString = try? container.decode(String.self, forKey: .acknowledgedTime) {
            let formatter = ISO8601DateFormatter()
            acknowledgedTime = formatter.date(from: dateString)
        } else {
            acknowledgedTime = nil
        }
        
        if let timestamp = try? container.decode(Double.self, forKey: .resolvedTime) {
            resolvedTime = Date(timeIntervalSince1970: timestamp)
        } else if let dateString = try? container.decode(String.self, forKey: .resolvedTime) {
            let formatter = ISO8601DateFormatter()
            resolvedTime = formatter.date(from: dateString)
        } else {
            resolvedTime = nil
        }
        
        acknowledgedBy = try container.decodeIfPresent(String.self, forKey: .acknowledgedBy)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(incidentID, forKey: .incidentID)
        try container.encodeIfPresent(deviceIP, forKey: .deviceIP)
        try container.encodeIfPresent(deviceName, forKey: .deviceName)
        try container.encode(summary, forKey: .summary)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(severity.rawValue, forKey: .severity)
        try container.encode(status.rawValue, forKey: .status)
        try container.encode(state.rawValue, forKey: .state)
        try container.encode(acknowledged, forKey: .acknowledged)
        try container.encodeIfPresent(ackUser, forKey: .ackUser)
        try container.encodeIfPresent(closedAt?.timeIntervalSince1970, forKey: .closedAt)
        try container.encodeIfPresent(incidentState, forKey: .incidentState)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encode(startTime.timeIntervalSince1970, forKey: .startTime)
        try container.encodeIfPresent(acknowledgedTime?.timeIntervalSince1970, forKey: .acknowledgedTime)
        try container.encodeIfPresent(resolvedTime?.timeIntervalSince1970, forKey: .resolvedTime)
        try container.encodeIfPresent(acknowledgedBy, forKey: .acknowledgedBy)
    }
}

extension NetreoIncident.CodingKeys: CaseIterable {
    static var allCases: [NetreoIncident.CodingKeys] {
        return [.incidentID, .deviceIP, .deviceName, .summary, .description, .severity, .status, .state, .acknowledged, .ackUser, .closedAt, .incidentState, .category, .startTime, .acknowledgedTime, .resolvedTime, .acknowledgedBy]
    }
}