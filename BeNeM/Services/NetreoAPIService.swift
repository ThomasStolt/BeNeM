import Foundation
import SwiftUI

class NetreoAPIService: ObservableObject {
    private let configuration: NetreoAPIConfiguration
    private let urlSession: URLSession
    private let jsonDecoder: JSONDecoder
    
    init(configuration: NetreoAPIConfiguration) {
        self.configuration = configuration
        
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.timeout
        sessionConfig.timeoutIntervalForResource = configuration.timeout * 2
        self.urlSession = URLSession(configuration: sessionConfig)
        
        self.jsonDecoder = JSONDecoder()
        self.jsonDecoder.dateDecodingStrategy = .iso8601
    }
    
    convenience init(baseURL: String, apiKey: String, pin: String? = nil, version: NetreoAPIConfiguration.APIVersion = .legacy) {
        let config = NetreoAPIConfiguration(baseURL: baseURL, apiKey: apiKey, pin: pin, version: version)
        self.init(configuration: config)
    }
    
    func fetchDevices() async throws -> [NetreoDevice] {
        let endpoint = NetreoEndpoint.deviceList
        
        switch configuration.version {
        case .legacy:
            return try await performLegacyDeviceRequest(endpoint: endpoint, parameters: baseParameters())
        case .v1, .v2, .openapi:
            return try await performModernDeviceRequest(endpoint: endpoint)
        }
    }
    
    func addDevice(ip: String, snmpPublic: String, name: String? = nil) async throws -> Bool {
        let endpoint = NetreoEndpoint.deviceAdd
        var parameters = baseParameters()
        parameters["ip"] = ip
        parameters["snmp_pub"] = snmpPublic
        if let name = name {
            parameters["name"] = name
        }
        
        switch configuration.version {
        case .legacy:
            return try await performLegacyBoolRequest(endpoint: endpoint, parameters: parameters)
        case .v1, .v2, .openapi:
            let deviceData: [String: Any] = [
                "ip": ip,
                "snmp_community": snmpPublic,
                "name": name ?? ip
            ]
            return try await performModernBoolRequest(endpoint: endpoint, body: deviceData)
        }
    }
    
    func deleteDevice(identifier: String) async throws -> Bool {
        let endpoint = NetreoEndpoint.deviceDelete(identifier)
        
        switch configuration.version {
        case .legacy:
            var parameters = baseParameters()
            parameters["name"] = identifier
            return try await performLegacyBoolRequest(endpoint: endpoint, parameters: parameters)
        case .v1, .v2, .openapi:
            return try await performModernBoolRequest(endpoint: endpoint)
        }
    }
    
    func renameDevice(identifier: String, newName: String) async throws -> Bool {
        let endpoint = NetreoEndpoint.deviceRename(identifier, newName)
        
        switch configuration.version {
        case .legacy:
            var parameters = baseParameters()
            parameters["device_id"] = identifier
            parameters["new_name"] = newName
            return try await performLegacyBoolRequest(endpoint: endpoint, parameters: parameters)
        case .v1, .v2, .openapi:
            let renameData = ["name": newName]
            return try await performModernBoolRequest(endpoint: endpoint, body: renameData)
        }
    }
    
    func fetchDevicePerformance(identifier: String) async throws -> [DevicePerformance] {
        // Return empty array for now - can be implemented later
        return []
    }
    
    func acknowledgeIncident(incidentID: String, user: String, comment: String = "From Mobile App") async throws -> Bool {
        var components = URLComponents(string: "\(configuration.baseURL)/utils/incident_ack.php")!
        components.queryItems = [
            URLQueryItem(name: "pwd",         value: configuration.apiKey),
            URLQueryItem(name: "ack_user",    value: user),
            URLQueryItem(name: "ack_comment", value: comment),
            URLQueryItem(name: "incident_id", value: incidentID)
        ]
        if let pin = configuration.pin {
            components.queryItems?.append(URLQueryItem(name: "pin", value: pin))
        }
        guard let url = components.url else { return false }
        let (_, response) = try await urlSession.data(from: url)
        return (response as? HTTPURLResponse)?.statusCode ?? 0 < 400
    }

    func unacknowledgeIncident(incidentID: String, user: String = "mobile", comment: String = "De-Acked from Mobile App") async throws -> Bool {
        guard let url = URL(string: "\(configuration.baseURL)/fw/index.php?r=restful/incident/unacknowledge") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var bodyParts = [
            "password=\(configuration.apiKey)",
            "incident_id=\(incidentID)",
            "user=\(user)",
            "comment=\(comment)",
            "unacknowledge=1"
        ]
        if let pin = configuration.pin {
            bodyParts.append("pin=\(pin)")
        }
        request.httpBody = bodyParts.joined(separator: "&").data(using: .utf8)
        let (_, response) = try await urlSession.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? 0 < 400
    }

    func fetchIncidentDetail(incidentID: String) async throws -> IncidentDetail? {
        var components = URLComponents(string: "\(configuration.baseURL)/api/incident_api.php")!
        components.queryItems = [
            URLQueryItem(name: "pwd",         value: configuration.apiKey),
            URLQueryItem(name: "method",      value: "getincidentdetail"),
            URLQueryItem(name: "incident_id", value: incidentID)
        ]
        if let pin = configuration.pin {
            components.queryItems?.append(URLQueryItem(name: "pin", value: pin))
        }
        guard let url = components.url else { return nil }
        let (data, _) = try await urlSession.data(from: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return IncidentDetail.parse(from: json)
    }

    func fetchIncidentAlarmCounts(incidentID: String) async throws -> [AlarmColor: Int] {
        var components = URLComponents(string: "\(configuration.baseURL)/api/incident_api.php")!
        components.queryItems = [
            URLQueryItem(name: "pwd", value: configuration.apiKey),
            URLQueryItem(name: "method", value: "getincidentdetail"),
            URLQueryItem(name: "incident_id", value: incidentID)
        ]
        if let pin = configuration.pin {
            components.queryItems?.append(URLQueryItem(name: "pin", value: pin))
        }
        guard let url = components.url else { return [:] }

        let (data, _) = try await urlSession.data(from: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let incident = json["incident"] as? [String: Any],
              let detail = incident["detail"] as? [String: Any] else { return [:] }

        // Alarme aus primary_alarm_log + relatedalarms sammeln
        var alarmEntries: [[String: Any]] = []
        if let primary = detail["primary_alarm_log"] as? [[String: Any]] {
            alarmEntries.append(contentsOf: primary)
        }
        if let related = detail["relatedalarms"] as? [[String: Any]] {
            alarmEntries.append(contentsOf: related)
        }

        var counts: [AlarmColor: Int] = [:]
        for alarm in alarmEntries {
            let color = AlarmColor.fromState(alarm["state"] as? String)
            counts[color, default: 0] += 1
        }
        return counts
    }

    func fetchIncidents() async throws -> [NetreoIncident] {
        switch configuration.version {
        case .legacy:
            return try await performLegacyIncidentRequest()
        case .v1, .v2, .openapi:
            return try await performModernIncidentRequest()
        }
    }
    
    private func baseParameters() -> [String: Any] {
        var parameters: [String: Any] = ["pwd": configuration.apiKey]
        if let pin = configuration.pin {
            parameters["pin"] = pin
        }
        return parameters
    }
    
    private func performLegacyDeviceRequest(
        endpoint: NetreoEndpoint,
        parameters: [String: Any]
    ) async throws -> [NetreoDevice] {
        let url = URL(string: configuration.endpoint(for: endpoint.path(for: configuration.version)))!
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.httpMethod(for: configuration.version).rawValue
        
        if endpoint.httpMethod(for: configuration.version) == .POST ||
           endpoint.httpMethod(for: configuration.version) == .PUT {
            let bodyString = parameters.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
            request.httpBody = bodyString.data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            throw APIError.httpError(httpResponse.statusCode, data)
        }
        
        // Try to parse response
        if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let success = jsonObject["success"] as? Bool ?? true
            
            if !success {
                let errorMessage = jsonObject["error"] as? String ?? 
                                 jsonObject["failure"] as? String ?? 
                                 "Unknown error"
                throw APIError.requestFailed(errorMessage)
            }
            
            // For testing, return some mock devices if no real data
            return createMockDevices()
        }
        
        throw APIError.invalidResponse
    }
    
    private func performModernDeviceRequest(endpoint: NetreoEndpoint) async throws -> [NetreoDevice] {
        let url = URL(string: configuration.endpoint(for: endpoint.path(for: configuration.version)))!
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.httpMethod(for: configuration.version).rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            throw APIError.httpError(httpResponse.statusCode, data)
        }
        
        // For testing, return some mock devices
        return createMockDevices()
    }
    
    private func performLegacyBoolRequest(
        endpoint: NetreoEndpoint,
        parameters: [String: Any]
    ) async throws -> Bool {
        let url = URL(string: configuration.endpoint(for: endpoint.path(for: configuration.version)))!
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.httpMethod(for: configuration.version).rawValue
        
        let bodyString = parameters.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            throw APIError.httpError(httpResponse.statusCode, data)
        }
        
        if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return jsonObject["success"] as? Bool ?? false
        }
        
        return true
    }
    
    private func performModernBoolRequest(endpoint: NetreoEndpoint, body: [String: Any]? = nil) async throws -> Bool {
        let url = URL(string: configuration.endpoint(for: endpoint.path(for: configuration.version)))!
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.httpMethod(for: configuration.version).rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        
        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            throw APIError.httpError(httpResponse.statusCode, data)
        }
        
        return true
    }
    
    private func performLegacyIncidentRequest() async throws -> [NetreoIncident] {
        let endpoint = NetreoEndpoint.incidents
        var parameters = baseParameters()
        parameters["method"] = "getincidents"
        
        let urlString = configuration.endpoint(for: endpoint.path(for: configuration.version))
        print("Fetching incidents from URL: \(urlString)")
        print("Parameters: \(parameters)")
        
        let url = URL(string: urlString)!
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.httpMethod(for: configuration.version).rawValue
        
        let bodyString = parameters.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            throw APIError.httpError(httpResponse.statusCode, data)
        }
        
        // Debug: Print raw response
        if let responseString = String(data: data, encoding: .utf8) {
            print("Raw incident API response: \(responseString)")
        }
        
        // Try to parse response
        if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            print("Parsed incident JSON object: \(jsonObject)")

            // Debug: Top-level Keys und ersten Incident-Eintrag speichern
            let topLevelKeys = Array(jsonObject.keys).sorted().joined(separator: ", ")
            var debugInfo = "Top-level keys: \(topLevelKeys)\n\n"

            let allArrayKeys = jsonObject.keys.filter { jsonObject[$0] is [[String: Any]] || jsonObject[$0] is [Any] }
            for key in allArrayKeys.sorted() {
                if let arr = jsonObject[key] as? [[String: Any]], let first = arr.first {
                    debugInfo += "[\(key)] first entry keys:\n"
                    debugInfo += first.map { "  \($0.key) = \($0.value)" }.sorted().joined(separator: "\n")
                    debugInfo += "\n"
                }
            }
            // Falls kein Array: gesamtes Objekt anzeigen
            if allArrayKeys.isEmpty {
                debugInfo += "Kein Array gefunden. Gesamte Antwort:\n"
                debugInfo += jsonObject.map { "  \($0.key) = \($0.value)" }.sorted().joined(separator: "\n")
            }
            UserDefaults.standard.set(debugInfo, forKey: "debug_incident_fields")

            let success = jsonObject["success"] as? Bool ?? true

            if !success {
                let errorMessage = jsonObject["error"] as? String ??
                                 jsonObject["failure"] as? String ??
                                 "Unknown error"
                throw APIError.requestFailed(errorMessage)
            }

            // Try to parse incidents from response data
            if let incidentsArray = jsonObject["active_incidents"] as? [[String: Any]] {
                return try parseIncidentsFromNetreoFormat(from: incidentsArray)
            } else if let incidentsArray = jsonObject["incidents"] as? [[String: Any]] {
                return try parseIncidents(from: incidentsArray)
            } else if let dataArray = jsonObject["data"] as? [[String: Any]] {
                return try parseIncidents(from: dataArray)
            } else {
                return []
            }
        }
        
        throw APIError.invalidResponse
    }
    
    private func performModernIncidentRequest() async throws -> [NetreoIncident] {
        let endpoint = NetreoEndpoint.incidents
        let url = URL(string: configuration.endpoint(for: endpoint.path(for: configuration.version)))!
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.httpMethod(for: configuration.version).rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            throw APIError.httpError(httpResponse.statusCode, data)
        }
        
        // Debug: rohe Antwort speichern
        if let rawString = String(data: data.prefix(2000), encoding: .utf8) {
            UserDefaults.standard.set("Modern API response:\n\(rawString)", forKey: "debug_incident_fields")
        }

        // Try to decode incidents from response
        do {
            let incidentsResponse = try jsonDecoder.decode([NetreoIncident].self, from: data)
            return incidentsResponse
        } catch {
            if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let incidentsArray = jsonObject["incidents"] as? [[String: Any]] {
                return try parseIncidents(from: incidentsArray)
            } else if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return try parseIncidents(from: jsonArray)
            }
            return []
        }
    }
    
    private func parseIncidentsFromNetreoFormat(from array: [[String: Any]]) throws -> [NetreoIncident] {
        var incidents: [NetreoIncident] = []
        print("Parsing \(array.count) incidents from Netreo format")

        // Debug: ersten Incident komplett in UserDefaults speichern
        if let first = array.first {
            let debugLines = first.map { key, value in "\(key) = \(value)" }.sorted()
            let debugString = debugLines.joined(separator: "\n")
            UserDefaults.standard.set(debugString, forKey: "debug_incident_fields")
            print("DEBUG first incident fields:\n\(debugString)")
        }
        
        for (index, incidentData) in array.enumerated() {
            do {
                print("Parsing incident \(index + 1)")
                
                // Parse incident ID more carefully
                let incidentID: String
                if let intID = incidentData["incident_id"] as? Int {
                    incidentID = String(intID)
                    print("Parsed incident_id as Int: \(intID) -> \(incidentID)")
                } else if let stringID = incidentData["incident_id"] as? String {
                    incidentID = stringID
                    print("Parsed incident_id as String: \(stringID)")
                } else {
                    // Try alternative field names that might contain the ID
                    if let altID = incidentData["id"] as? Int {
                        incidentID = String(altID)
                        print("Using 'id' field: \(altID)")
                    } else if let altStringID = incidentData["id"] as? String {
                        incidentID = altStringID
                        print("Using 'id' field as string: \(altStringID)")
                    } else {
                        incidentID = "unknown_\(index)"
                        print("No valid ID found, using: \(incidentID)")
                    }
                    print("Available keys in incident data: \(Array(incidentData.keys))")
                }
                let title = incidentData["title"] as? String ?? "Unknown"
                let deviceName = incidentData["name"] as? String
                let stateString = incidentData["incident_state"] as? String ?? "OPEN"

                let status: NetreoIncident.IncidentStatus = stateString == "ACKNOWLEDGED" ? .acknowledged : .active

                // Netreo liefert kein Severity-Feld in diesem Endpunkt.
                // Severity aus bekannten Feldern lesen, sonst .critical als sinnvoller Default
                // für aktive Service-Check-Failures.
                let severityRaw = incidentData["severity"] as? String
                    ?? incidentData["alert_level"] as? String
                    ?? incidentData["level"] as? String
                    ?? incidentData["priority"] as? String
                    ?? incidentData["type_name"] as? String
                let severity: NetreoIncident.IncidentSeverity
                switch severityRaw?.lowercased() {
                case "critical", "1":   severity = .critical
                case "major", "2":      severity = .major
                case "minor", "3":      severity = .minor
                case "warning", "4":    severity = .warning
                case "informational", "info", "5": severity = .informational
                default:
                    if let n = incidentData["severity"] as? Int
                        ?? incidentData["alert_level"] as? Int
                        ?? incidentData["level"] as? Int
                        ?? incidentData["priority"] as? Int {
                        switch n {
                        case 1: severity = .critical
                        case 2: severity = .major
                        case 3: severity = .minor
                        case 4: severity = .warning
                        default: severity = .informational
                        }
                    } else {
                        // Kein Severity-Feld vorhanden → Critical als Default
                        severity = .critical
                    }
                }

                // Startzeit aus open_time parsen
                let startTime: Date
                if let openTimeStr = incidentData["open_time"] as? String {
                    let iso = ISO8601DateFormatter()
                    iso.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
                    startTime = iso.date(from: openTimeStr) ?? Date()
                } else {
                    startTime = Date()
                }
                
                let incident = NetreoIncident(
                    incidentID: incidentID,
                    deviceIP: nil,
                    deviceName: deviceName,
                    summary: title,
                    description: nil,
                    severity: severity,
                    status: status,
                    category: "Network",
                    startTime: startTime
                )
                
                incidents.append(incident)
                print("Successfully parsed incident \(incidentID)")
            } catch {
                print("Failed to parse incident \(index + 1): \(error)")
                continue
            }
        }
        
        print("Successfully parsed \(incidents.count) incidents")
        return incidents
    }
    
    private func parseIncidents(from array: [[String: Any]]) throws -> [NetreoIncident] {
        var incidents: [NetreoIncident] = []
        
        for incidentData in array {
            let incidentJSON = try JSONSerialization.data(withJSONObject: incidentData)
            let incident = try jsonDecoder.decode(NetreoIncident.self, from: incidentJSON)
            incidents.append(incident)
        }
        
        return incidents
    }
    
    private func createMockDevices() -> [NetreoDevice] {
        return [
            NetreoDevice(
                ip: "192.168.1.1",
                name: "Router",
                hostname: "main-router",
                status: .up,
                deviceType: "router",
                lastUpdated: Date(),
                siteID: "1",
                categoryID: "1",
                snmpCommunity: "public",
                isActive: true,
                additionalProperties: [:]
            ),
            NetreoDevice(
                ip: "192.168.1.10",
                name: "Switch",
                hostname: "core-switch",
                status: .up,
                deviceType: "switch",
                lastUpdated: Date(),
                siteID: "1",
                categoryID: "2",
                snmpCommunity: "public",
                isActive: true,
                additionalProperties: [:]
            ),
            NetreoDevice(
                ip: "192.168.1.100",
                name: "Server",
                hostname: "web-server",
                status: .warning,
                deviceType: "server",
                lastUpdated: Date(),
                siteID: "1",
                categoryID: "3",
                snmpCommunity: "public",
                isActive: true,
                additionalProperties: [:]
            )
        ]
    }
}

enum AlarmColor: String, CaseIterable, Hashable {
    case red, orange, yellow, green, blue, grey

    var color: Color {
        switch self {
        case .red:    return .red
        case .orange: return .orange
        case .yellow: return Color(red: 0.75, green: 0.55, blue: 0)
        case .green:  return .green
        case .blue:   return .blue
        case .grey:   return Color(.systemGray)
        }
    }

    // Mappt den "state"-Wert aus primary_alarm_log auf eine Farbe
    // Bekannte Werte: "WARNING", "CRITICAL", "MAJOR", "MINOR", "OK", "OPEN", "ACKNOWLEDGED"
    static func fromState(_ state: String?) -> AlarmColor {
        switch state?.uppercased() {
        case "CRITICAL":                    return .red
        case "MAJOR":                       return .orange
        case "WARNING", "MINOR":            return .yellow
        case "OK", "RESOLVED", "CLOSED":    return .green
        case "ACKNOWLEDGED":                return .blue
        default:                            return .grey
        }
    }
}

enum APIError: Error, LocalizedError {
    case requestFailed(String)
    case invalidResponse
    case networkError
    case httpError(Int, Data?)
    case decodingError(Error)
    case configurationError(String)
    
    var errorDescription: String? {
        switch self {
        case .requestFailed(let message):
            return "Request failed: \(message)"
        case .invalidResponse:
            return "Invalid response from server"
        case .networkError:
            return "Network error occurred"
        case .httpError(let statusCode, let data):
            var message = "HTTP error \(statusCode)"
            if let data = data,
               let errorString = String(data: data, encoding: .utf8) {
                message += ": \(errorString)"
            }
            return message
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        }
    }
}