import Foundation

struct NetreoDevice: Codable, Identifiable {
    let id: String
    let ip: String
    let name: String?
    let hostname: String?
    let status: DeviceStatus
    let deviceType: String?
    let lastUpdated: Date
    let siteID: String?
    let categoryID: String?
    let snmpCommunity: String?
    let isActive: Bool
    let additionalProperties: [String: AnyCodable]
    
    init(ip: String, name: String?, hostname: String?, status: DeviceStatus, deviceType: String?, lastUpdated: Date, siteID: String?, categoryID: String?, snmpCommunity: String?, isActive: Bool, additionalProperties: [String: AnyCodable]) {
        self.id = ip
        self.ip = ip
        self.name = name
        self.hostname = hostname
        self.status = status
        self.deviceType = deviceType
        self.lastUpdated = lastUpdated
        self.siteID = siteID
        self.categoryID = categoryID
        self.snmpCommunity = snmpCommunity
        self.isActive = isActive
        self.additionalProperties = additionalProperties
    }
    
    enum DeviceStatus: String, Codable, CaseIterable {
        case up = "up"
        case down = "down"
        case warning = "warning"
        case critical = "critical"
        case unknown = "unknown"
        case maintenance = "maintenance"
    }
    
    enum CodingKeys: String, CodingKey {
        case ip, name, hostname, status, deviceType, lastUpdated, siteID, categoryID, snmpCommunity, isActive
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        ip = try container.decode(String.self, forKey: .ip)
        id = ip
        name = try container.decodeIfPresent(String.self, forKey: .name)
        hostname = try container.decodeIfPresent(String.self, forKey: .hostname)
        
        if let statusString = try? container.decode(String.self, forKey: .status) {
            status = DeviceStatus(rawValue: statusString.lowercased()) ?? .unknown
        } else {
            status = .unknown
        }
        
        deviceType = try container.decodeIfPresent(String.self, forKey: .deviceType)
        
        if let timestamp = try? container.decode(Double.self, forKey: .lastUpdated) {
            lastUpdated = Date(timeIntervalSince1970: timestamp)
        } else if let dateString = try? container.decode(String.self, forKey: .lastUpdated) {
            let formatter = ISO8601DateFormatter()
            lastUpdated = formatter.date(from: dateString) ?? Date()
        } else {
            lastUpdated = Date()
        }
        
        siteID = try container.decodeIfPresent(String.self, forKey: .siteID)
        categoryID = try container.decodeIfPresent(String.self, forKey: .categoryID)
        snmpCommunity = try container.decodeIfPresent(String.self, forKey: .snmpCommunity)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        
        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKeys.self)
        var additionalProps: [String: AnyCodable] = [:]
        
        for key in dynamicContainer.allKeys {
            if !CodingKeys.allCases.map(\.rawValue).contains(key.stringValue) {
                if let value = try? dynamicContainer.decode(AnyCodable.self, forKey: key) {
                    additionalProps[key.stringValue] = value
                }
            }
        }
        additionalProperties = additionalProps
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(ip, forKey: .ip)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(hostname, forKey: .hostname)
        try container.encode(status.rawValue, forKey: .status)
        try container.encodeIfPresent(deviceType, forKey: .deviceType)
        try container.encode(lastUpdated.timeIntervalSince1970, forKey: .lastUpdated)
        try container.encodeIfPresent(siteID, forKey: .siteID)
        try container.encodeIfPresent(categoryID, forKey: .categoryID)
        try container.encodeIfPresent(snmpCommunity, forKey: .snmpCommunity)
        try container.encode(isActive, forKey: .isActive)
        
        var dynamicContainer = encoder.container(keyedBy: DynamicCodingKeys.self)
        for (key, value) in additionalProperties {
            let codingKey = DynamicCodingKeys(stringValue: key)!
            try dynamicContainer.encode(value, forKey: codingKey)
        }
    }
}


struct AnyCodable: Codable {
    let value: Any
    
    init<T>(_ value: T?) {
        self.value = value ?? ()
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            value = dictValue.mapValues { $0.value }
        } else {
            value = ()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let arrayValue as [Any]:
            try container.encode(arrayValue.map(AnyCodable.init))
        case let dictValue as [String: Any]:
            try container.encode(dictValue.mapValues(AnyCodable.init))
        default:
            try container.encodeNil()
        }
    }
}

struct DynamicCodingKeys: CodingKey {
    var stringValue: String
    var intValue: Int?
    
    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }
    
    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

extension NetreoDevice.CodingKeys: CaseIterable {
    static var allCases: [NetreoDevice.CodingKeys] {
        return [.ip, .name, .hostname, .status, .deviceType, .lastUpdated, .siteID, .categoryID, .snmpCommunity, .isActive]
    }
}

