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
    var status: IncidentStatus
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
    
    enum CodingKeys: String, CodingKey {
        case incidentID = "incident_id"
        case deviceIP = "device_ip"
        case deviceName = "device_name"
        case summary
        case description
        case severity
        case status
        case incidentState = "incident_state"
        case category
        case startTime = "start_time"
        case acknowledgedTime = "acknowledged_time"
        case resolvedTime = "resolved_time"
        case acknowledgedBy = "acknowledged_by"
    }
    
    init(incidentID: String, deviceIP: String?, deviceName: String?, summary: String, description: String?, severity: IncidentSeverity, status: IncidentStatus, incidentState: String = "OPEN", category: String?, startTime: Date, acknowledgedTime: Date? = nil, resolvedTime: Date? = nil, acknowledgedBy: String? = nil) {
        self.incidentID = incidentID
        self.deviceIP = deviceIP
        self.deviceName = deviceName
        self.summary = summary
        self.description = description
        self.severity = severity
        self.status = status
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
        
        if let statusString = try? container.decode(String.self, forKey: .status) {
            status = IncidentStatus(rawValue: statusString.lowercased()) ?? .active
        } else {
            status = .active
        }
        
        incidentState = (try? container.decodeIfPresent(String.self, forKey: .incidentState)) ?? "OPEN"
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
        try container.encodeIfPresent(category, forKey: .category)
        try container.encode(startTime.timeIntervalSince1970, forKey: .startTime)
        try container.encodeIfPresent(acknowledgedTime?.timeIntervalSince1970, forKey: .acknowledgedTime)
        try container.encodeIfPresent(resolvedTime?.timeIntervalSince1970, forKey: .resolvedTime)
        try container.encodeIfPresent(acknowledgedBy, forKey: .acknowledgedBy)
    }
}

extension NetreoIncident.CodingKeys: CaseIterable {
    static var allCases: [NetreoIncident.CodingKeys] {
        return [.incidentID, .deviceIP, .deviceName, .summary, .description, .severity, .status, .category, .startTime, .acknowledgedTime, .resolvedTime, .acknowledgedBy]
    }
}