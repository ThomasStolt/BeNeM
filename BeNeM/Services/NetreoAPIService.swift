import Foundation
import SwiftUI

struct PerformanceMetric {
    let instanceDescr: String
    let value1: Double?   // primary value (e.g. % used, bytes used)
    let value2: Double?   // secondary value where applicable (e.g. bytes total)
}

struct PerformanceCategory {
    let id: String
    let name: String
}

struct PerformanceInstance {
    let key: String           // unique; interface instances are suffixed "-in" or "-out"
    let title: String
    let unit: String
    let statGroup: String     // value passed to metricFilterStatGroup
    let categoryId: String
    let valueKey: String      // "value1" or "value2" (outbound interface)
    let instanceDescr: String? // interface description for response filtering; nil for non-interface
}

struct PerformanceDataPoint {
    let timestamp: Date
    let value: Double
}

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
    
    private func formEncodedBody(_ params: [URLQueryItem]) -> Data? {
        var comps = URLComponents()
        comps.queryItems = params
        return comps.percentEncodedQuery?.data(using: .utf8)
    }

    private func addProxyToken(_ request: inout URLRequest) {
        guard !configuration.proxyToken.isEmpty else { return }
        request.setValue(configuration.proxyToken, forHTTPHeaderField: "X-Proxy-Token")
        if !configuration.bhnmURL.isEmpty {
            request.setValue(configuration.bhnmURL, forHTTPHeaderField: "X-BHNM-Target")
        }
    }

    func fetchDevices() async throws -> [NetreoDevice] {
        guard let url = URL(string: "\(configuration.baseURL)/fw/index.php?r=restful/devices/list") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addProxyToken(&request)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [URLQueryItem(name: "password", value: configuration.apiKey)]
        if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
        request.httpBody = formEncodedBody(params)
        let (data, _) = try await urlSession.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        // API returns either {"devices":[...]} or {"data":{"devices":[...]}}
        let devicesArray: [[String: Any]]
        if let arr = json["devices"] as? [[String: Any]] {
            devicesArray = arr
        } else if let nested = json["data"] as? [String: Any],
                  let arr = nested["devices"] as? [[String: Any]] {
            devicesArray = arr
        } else {
            return []
        }
        #if DEBUG
        if let first = devicesArray.first {
            let debugLines = first.map { "\($0.key) = \($0.value)" }.sorted()
            UserDefaults.standard.set(debugLines.joined(separator: "\n"), forKey: "debug_device_fields")
        }
        #endif
        return devicesArray.compactMap { parseRESTfulDevice(from: $0) }
    }

    func fetchDevicesPage(limit: Int? = nil, offset: Int = 0) async throws -> [NetreoDevice] {
        guard let url = URL(string: "\(configuration.baseURL)/fw/index.php?r=restful/devices/list") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addProxyToken(&request)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [URLQueryItem(name: "password", value: configuration.apiKey)]
        if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
        params.append(URLQueryItem(name: "recordStart", value: String(offset)))
        if let limit { params.append(URLQueryItem(name: "recordCount", value: String(limit))) }
        request.httpBody = formEncodedBody(params)
        let (data, _) = try await urlSession.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let devicesArray: [[String: Any]]
        if let arr = json["devices"] as? [[String: Any]] {
            devicesArray = arr
        } else if let nested = json["data"] as? [String: Any],
                  let arr = nested["devices"] as? [[String: Any]] {
            devicesArray = arr
        } else {
            return []
        }
        return devicesArray.compactMap { parseRESTfulDevice(from: $0) }
    }

    func findDeviceIndex(name: String) async throws -> String? {
        guard let url = URL(string: "\(configuration.baseURL)/fw/index.php?r=restful/devices/find") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addProxyToken(&request)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [
            URLQueryItem(name: "password", value: configuration.apiKey),
            URLQueryItem(name: "name",     value: name),
        ]
        if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
        request.httpBody = formEncodedBody(params)
        let (data, _) = try await urlSession.data(for: request)
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = arr.first else { return nil }
        return first["dev_index"] as? String
    }

    func fetchPerformanceCategories(deviceId: String) async throws -> [PerformanceCategory] {
        guard let url = URL(string: "\(configuration.baseURL)/fw/index.php?r=restful/devices/performance-category") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addProxyToken(&request)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [
            URLQueryItem(name: "password",   value: configuration.apiKey),
            URLQueryItem(name: "device_id",  value: deviceId),
        ]
        if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
        request.httpBody = formEncodedBody(params)
        let (data, _) = try await urlSession.data(for: request)
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { dict -> PerformanceCategory? in
            let rawId = (dict["id"] as? String) ?? (dict["id"] as? Int).map(String.init)
            guard let id = rawId else { return nil }
            let name = (dict["category"] as? String) ?? (dict["cat"] as? String) ?? ""
            guard !name.isEmpty else { return nil }
            return PerformanceCategory(id: id, name: name)
        }
    }

    func fetchPerformanceInstances(deviceId: String, category: PerformanceCategory) async throws -> [PerformanceInstance] {
        guard let url = URL(string: "\(configuration.baseURL)/fw/index.php?r=restful/devices/performance-instance-per-category") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addProxyToken(&request)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [
            URLQueryItem(name: "password",  value: configuration.apiKey),
            URLQueryItem(name: "device_id", value: deviceId),
            URLQueryItem(name: "id",        value: category.id),
        ]
        if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
        request.httpBody = formEncodedBody(params)
        let (data, _) = try await urlSession.data(for: request)
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

        var instances: [PerformanceInstance] = []
        for dict in arr {
            let rawKey = (dict["key"] as? String) ?? (dict["key"] as? Int).map(String.init) ?? ""
            let type_ = dict["type"] as? String ?? ""

            if type_ == "interface" {
                // Interface entries produce two instances: inbound and outbound
                // The "-in"/"-out" suffix is REQUIRED to ensure cardStates dictionary keys are unique
                let description = dict["description"] as? String ?? rawKey
                let bwUnit = (dict["bandwidth"] as? [String: Any])?["unit"] as? String ?? "%"
                instances.append(PerformanceInstance(
                    key: "\(rawKey)-in",
                    title: "\(description) — In",
                    unit: bwUnit,
                    statGroup: category.name,
                    categoryId: category.id,
                    valueKey: "value1",
                    instanceDescr: description
                ))
                instances.append(PerformanceInstance(
                    key: "\(rawKey)-out",
                    title: "\(description) — Out",
                    unit: bwUnit,
                    statGroup: category.name,
                    categoryId: category.id,
                    valueKey: "value2",
                    instanceDescr: description
                ))
            } else {
                let title = dict["title"] as? String ?? rawKey
                let unit  = dict["unit"]  as? String ?? ""
                instances.append(PerformanceInstance(
                    key: rawKey,
                    title: title,
                    unit: unit,
                    statGroup: category.name,
                    categoryId: category.id,
                    valueKey: "value1",
                    instanceDescr: nil
                ))
            }
        }
        return instances
    }

    func fetchTimeSeries(
        deviceName: String,
        instance: PerformanceInstance,
        timeFrame: TimeFrame
    ) async throws -> [PerformanceDataPoint] {
        let urlString = "\(configuration.baseURL)/fw/index.php?r=restful/devices/get-time-series-metrics"
        guard let url = URL(string: urlString) else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addProxyToken(&request)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [
            URLQueryItem(name: "password",               value: configuration.apiKey),
            URLQueryItem(name: "groupFilterBy",          value: "device"),
            URLQueryItem(name: "groupFilterValue",       value: deviceName),
            URLQueryItem(name: "metricFilterStatGroup",  value: instance.statGroup),
            URLQueryItem(name: "metricFilterUnits",      value: instance.unit),
            URLQueryItem(name: "timeFrameFilterBy",      value: "time_offset"),
            URLQueryItem(name: "timeFrameFilterValue",   value: timeFrame.rawValue),
            URLQueryItem(name: "returnFormatFilterBy",   value: "average"),
        ]
        if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
        request.httpBody = formEncodedBody(params)
        let (data, _) = try await urlSession.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let metrics = json["metrics"] as? [[String: Any]] else { return [] }
        return metrics.compactMap { dict -> PerformanceDataPoint? in
            // For interface instances, filter to only the matching interface description
            if let filter = instance.instanceDescr {
                let descr = dict["instanceDescr"] as? String ?? ""
                guard descr == filter else { return nil }
            }
            guard let tsString = dict["timeStamp"] as? String,
                  let ts = Double(tsString) else { return nil }
            let rawValue = dict[instance.valueKey]
            let value: Double?
            if let s = rawValue as? String { value = Double(s) }
            else if let d = rawValue as? Double { value = d }
            else { value = nil }
            guard let v = value else { return nil }
            return PerformanceDataPoint(timestamp: Date(timeIntervalSince1970: ts), value: v)
        }
    }

    func fetchPerformanceMetrics(
        deviceName: String,
        statGroup: String,
        units: String
    ) async throws -> [PerformanceMetric] {
        let urlString = "\(configuration.baseURL)/fw/index.php?r=restful/devices/get-time-series-metrics"
        guard let url = URL(string: urlString) else { return [] }

        var params = [
            URLQueryItem(name: "password",               value: configuration.apiKey),
            URLQueryItem(name: "metricFilterStatGroup",  value: statGroup),
            URLQueryItem(name: "metricFilterUnits",      value: units),
            URLQueryItem(name: "groupFilterBy",          value: "device"),
            URLQueryItem(name: "groupFilterValue",       value: deviceName),
            URLQueryItem(name: "timeFrameFilterBy",      value: "time_offset"),
            URLQueryItem(name: "timeFrameFilterValue",   value: "Last 24 Hours"),
            URLQueryItem(name: "returnFormatFilterBy",   value: "average"),
        ]
        if let pin = configuration.pin {
            params.append(URLQueryItem(name: "pin", value: pin))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addProxyToken(&request)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncodedBody(params)

        let (data, _) = try await urlSession.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let metrics = json["metrics"] as? [[String: Any]] else { return [] }

        return metrics.compactMap { dict -> PerformanceMetric? in
            let descr = dict["instanceDescr"] as? String ?? ""
            let v1 = (dict["value1"] as? String).flatMap(Double.init)
                   ?? dict["value1"] as? Double
            let v2 = (dict["value2"] as? String).flatMap(Double.init)
                   ?? dict["value2"] as? Double
            return PerformanceMetric(instanceDescr: descr, value1: v1, value2: v2)
        }
    }

    /// Fetches metrics for a device with a given stat group filter and stores the raw
    /// JSON response in UserDefaults for inspection in Settings → Debug.
    func fetchRawMetricsResponse(deviceName: String, statGroup: String, units: String) async {
        let urlString = "\(configuration.baseURL)/fw/index.php?r=restful/devices/get-time-series-metrics"
        guard let url = URL(string: urlString) else { return }
        var params = [
            URLQueryItem(name: "password",               value: configuration.apiKey),
            URLQueryItem(name: "groupFilterBy",          value: "device"),
            URLQueryItem(name: "groupFilterValue",       value: deviceName),
            URLQueryItem(name: "timeFrameFilterBy",      value: "time_offset"),
            URLQueryItem(name: "timeFrameFilterValue",   value: "Last 24 Hours"),
            URLQueryItem(name: "returnFormatFilterBy",   value: "average"),
        ]
        if !statGroup.isEmpty { params.append(URLQueryItem(name: "metricFilterStatGroup", value: statGroup)) }
        if !units.isEmpty     { params.append(URLQueryItem(name: "metricFilterUnits",     value: units)) }
        if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addProxyToken(&request)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncodedBody(params)
        guard let (data, _) = try? await urlSession.data(for: request),
              let raw = String(data: data, encoding: .utf8) else { return }
        // Truncate to 2000 chars to fit reasonably in UserDefaults
        let truncated = raw.count > 2000 ? String(raw.prefix(2000)) + "…" : raw
        UserDefaults.standard.set(truncated, forKey: "debug_raw_metrics_response")
    }

    private func parseRESTfulDevice(from dict: [String: Any]) -> NetreoDevice? {
        guard let ip = dict["ip"] as? String else { return nil }
        let isActive  = (dict["poll"]    as? String) == "1"
        let isMonitor = (dict["monitor"] as? String) == "1"
        let lastUpdated: Date = {
            if let ts = dict["create_time"] as? String, let unix = Double(ts) {
                return Date(timeIntervalSince1970: unix)
            }
            return Date()
        }()

        // Determine real alarm status from API fields.
        // BHNM returns alarm color in "alarm_color" (string or int), "up_status", "status", etc.
        let status: NetreoDevice.DeviceStatus = {
            // Try "alarm_color" as string: "red", "orange", "yellow", "green"
            if let color = (dict["alarm_color"] as? String)?.lowercased() {
                switch color {
                case "red":                  return .critical
                case "orange":               return .warning
                case "yellow":               return .warning
                case "green":                return .up
                default: break
                }
            }
            // Try "alarm_color" as int: 0=green,1=yellow,2=orange,3=red (common BHNM convention)
            if let colorInt = dict["alarm_color"] as? Int {
                switch colorInt {
                case 3:  return .critical
                case 2:  return .warning
                case 1:  return .warning
                case 0:  return .up
                default: break
                }
            }
            // Try string that may contain the int
            if let colorStr = dict["alarm_color"] as? String, let colorInt = Int(colorStr) {
                switch colorInt {
                case 3:  return .critical
                case 2:  return .warning
                case 1:  return .warning
                case 0:  return .up
                default: break
                }
            }
            // Try "status" field
            if let s = (dict["status"] as? String)?.lowercased() {
                switch s {
                case "critical", "down": return .critical
                case "warning":          return .warning
                case "up", "ok":         return .up
                default: break
                }
            }
            // Try "up_status" / "up" (1 = up, 0 = down)
            if let upStatus = dict["up_status"] as? Int {
                return upStatus == 1 ? .up : .down
            }
            // Fallback: if monitored and polling → up, else unknown
            return (isActive && isMonitor) ? .up : .unknown
        }()

        return NetreoDevice(
            ip: ip,
            name: dict["name"] as? String,
            hostname: dict["description"] as? String,
            status: status,
            deviceType: dict["model"] as? String,
            lastUpdated: lastUpdated,
            siteID: dict["site"] as? String,
            categoryID: dict["category"] as? String,
            snmpCommunity: nil,
            isActive: isActive,
            additionalProperties: [:]
        )
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
    

    // MARK: - Tactical Group Summaries

    /// Single endpoint replacing all incident-derived summary logic.
    /// groupingType: "category" | "site" | "app" (business workflows)
    func fetchTacticalOverviewSummaries(groupingType: String) async throws -> [GroupSummary] {
        guard let url = URL(string: "\(configuration.baseURL)/fw/index.php?r=restful/tactical-overview/data") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addProxyToken(&request)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [
            URLQueryItem(name: "password",      value: configuration.apiKey),
            URLQueryItem(name: "grouping_type", value: groupingType)
        ]
        if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
        request.httpBody = formEncodedBody(params)

        let (data, _) = try await urlSession.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        // Extract (green, blue, yellow, orange, red) from a Status dict for a given prefix.
        // BHNM status keys: ok → green, ack → blue, warn → yellow, un → orange, crit → red
        func statusCounts(_ status: [String: Any], prefix: String)
            -> (green: Int, blue: Int, yellow: Int, orange: Int, red: Int)
        {
            let ok   = status["\(prefix)ok_count"]   as? Int ?? 0
            let ack  = status["\(prefix)ack_count"]  as? Int ?? 0
            let warn = status["\(prefix)warn_count"] as? Int ?? 0
            let un   = status["\(prefix)un_count"]   as? Int ?? 0
            let crit = status["\(prefix)crit_count"] as? Int ?? 0
            return (ok, ack, warn, un, crit)
        }

        var result: [GroupSummary] = []
        for (name, value) in json {
            guard let group  = value as? [String: Any],
                  let status = group["Status"] as? [String: Any] else { continue }
            let h = statusCounts(status, prefix: "host_")
            let s = statusCounts(status, prefix: "service_")
            let t = statusCounts(status, prefix: "threshold_")
            let a = statusCounts(status, prefix: "anom_threshold_")
            guard h.green + h.blue + h.yellow + h.orange + h.red > 0 else { continue }
            let displayName = name.trimmingCharacters(in: .whitespaces).isEmpty ? "Unknown" : name
            result.append(GroupSummary(
                id: name, name: displayName,
                hostsGreen:       h.green,  hostsBlue:       h.blue,  hostsYellow:       h.yellow,
                hostsOrange:      h.orange, hostsRed:        h.red,
                servicesGreen:    s.green,  servicesBlue:    s.blue,  servicesYellow:    s.yellow,
                servicesOrange:   s.orange, servicesRed:     s.red,
                thresholdsGreen:  t.green,  thresholdsBlue:  t.blue,  thresholdsYellow:  t.yellow,
                thresholdsOrange: t.orange, thresholdsRed:   t.red,
                anomaliesGreen:   a.green,  anomaliesBlue:   a.blue,  anomaliesYellow:   a.yellow,
                anomaliesOrange:  a.orange, anomaliesRed:    a.red
            ))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    func acknowledgeIncident(incidentID: String, user: String, comment: String = "Acked from Mobile App") async throws -> Bool {
        guard let url = URL(string: "\(configuration.baseURL)/fw/index.php?r=restful/incident/acknowledge") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addProxyToken(&request)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [
            URLQueryItem(name: "password", value: configuration.apiKey),
            URLQueryItem(name: "incident_id", value: incidentID),
            URLQueryItem(name: "user", value: user),
            URLQueryItem(name: "comment", value: comment)
        ]
        if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
        request.httpBody = formEncodedBody(params)
        let (_, response) = try await urlSession.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? 0 < 400
    }

    func unacknowledgeIncident(incidentID: String, user: String = "mobile", comment: String = "De-Acked from Mobile App") async throws -> Bool {
        guard let url = URL(string: "\(configuration.baseURL)/fw/index.php?r=restful/incident/unacknowledge") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addProxyToken(&request)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [
            URLQueryItem(name: "password", value: configuration.apiKey),
            URLQueryItem(name: "incident_id", value: incidentID),
            URLQueryItem(name: "user", value: user),
            URLQueryItem(name: "comment", value: comment),
            URLQueryItem(name: "unacknowledge", value: "1")
        ]
        if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
        request.httpBody = formEncodedBody(params)
        let (_, response) = try await urlSession.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? 0 < 400
    }

    func fetchIncidentDetail(incidentID: String) async throws -> IncidentDetail? {
        guard var components = URLComponents(string: "\(configuration.baseURL)/api/incident_api.php") else { return nil }
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

    /// Fetches incident detail and returns both the alert_type and alarm color counts.
    /// alert_type values from BHNM: "Host", "Service", "Threshold" (case-insensitive).
    private func fetchIncidentAlarmData(incidentID: String) async -> (alertType: String, counts: [AlarmColor: Int]) {
        guard var components = URLComponents(string: "\(configuration.baseURL)/api/incident_api.php") else { return ("host", [:]) }
        components.queryItems = [
            URLQueryItem(name: "pwd",         value: configuration.apiKey),
            URLQueryItem(name: "method",      value: "getincidentdetail"),
            URLQueryItem(name: "incident_id", value: incidentID)
        ]
        if let pin = configuration.pin {
            components.queryItems?.append(URLQueryItem(name: "pin", value: pin))
        }
        guard let url = components.url,
              let (data, _) = try? await urlSession.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let incident = json["incident"] as? [String: Any],
              let detail = incident["detail"] as? [String: Any] else { return ("host", [:]) }

        let alertType = (incident["alert_type"] as? String ?? "host").lowercased()

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
        return (alertType, counts)
    }

    func fetchIncidentAlarmCounts(incidentID: String) async throws -> [AlarmColor: Int] {
        return await fetchIncidentAlarmData(incidentID: incidentID).counts
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
    
    private func performLegacyBoolRequest(
        endpoint: NetreoEndpoint,
        parameters: [String: Any]
    ) async throws -> Bool {
        let url = URL(string: configuration.endpoint(for: endpoint.path(for: configuration.version)))!
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.httpMethod(for: configuration.version).rawValue
        addProxyToken(&request)

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
        addProxyToken(&request)
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
        #if DEBUG
        print("Fetching incidents from URL: \(urlString)")
        print("Parameters: \(parameters)")
        #endif
        
        let url = URL(string: urlString)!
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.httpMethod(for: configuration.version).rawValue
        addProxyToken(&request)

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

        #if DEBUG
        if let responseString = String(data: data, encoding: .utf8) {
            print("Raw incident API response: \(responseString)")
        }
        #endif
        
        // Try to parse response — response may be a plain object or wrapped in an outer array
        let rawJSON = try? JSONSerialization.jsonObject(with: data)
        let jsonObject: [String: Any]?
        if let dict = rawJSON as? [String: Any] {
            jsonObject = dict
        } else if let arr = rawJSON as? [[String: Any]] {
            jsonObject = arr.first
        } else {
            jsonObject = nil
        }
        if let jsonObject = jsonObject {
            #if DEBUG
            print("Parsed incident JSON object: \(jsonObject)")
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
            if allArrayKeys.isEmpty {
                debugInfo += "Kein Array gefunden. Gesamte Antwort:\n"
                debugInfo += jsonObject.map { "  \($0.key) = \($0.value)" }.sorted().joined(separator: "\n")
            }
            UserDefaults.standard.set(debugInfo, forKey: "debug_incident_fields")
            #endif

            let success = jsonObject["success"] as? Bool ?? true

            if !success {
                let errorMessage = jsonObject["error"] as? String ??
                                 jsonObject["failure"] as? String ??
                                 "Unknown error"
                throw APIError.requestFailed(errorMessage)
            }

            // Try to parse incidents from response data
            if let activeArray = jsonObject["active_incidents"] as? [[String: Any]] {
                var result = try parseIncidentsFromNetreoFormat(from: activeArray, defaultStatus: nil)
                if let closedArray = jsonObject["closed_incidents"] as? [[String: Any]] {
                    result += try parseIncidentsFromNetreoFormat(from: closedArray, defaultStatus: .resolved)
                }
                return result
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
        addProxyToken(&request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            throw APIError.httpError(httpResponse.statusCode, data)
        }
        
        #if DEBUG
        if let rawString = String(data: data.prefix(2000), encoding: .utf8) {
            UserDefaults.standard.set("Modern API response:\n\(rawString)", forKey: "debug_incident_fields")
        }
        #endif

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
    
    private func parseIncidentsFromNetreoFormat(from array: [[String: Any]], defaultStatus: NetreoIncident.IncidentStatus? = nil) throws -> [NetreoIncident] {
        var incidents: [NetreoIncident] = []
        #if DEBUG
        print("Parsing \(array.count) incidents from Netreo format")
        if let first = array.first {
            let debugLines = first.map { key, value in "\(key) = \(value)" }.sorted()
            let debugString = debugLines.joined(separator: "\n")
            UserDefaults.standard.set(debugString, forKey: "debug_incident_fields")
            print("DEBUG first incident fields:\n\(debugString)")
        }
        #endif
        
        for (index, incidentData) in array.enumerated() {
            do {
                #if DEBUG
                print("Parsing incident \(index + 1)")
                #endif

                // Parse incident ID more carefully
                let incidentID: String
                if let intID = incidentData["incident_id"] as? Int {
                    incidentID = String(intID)
                    #if DEBUG
                    print("Parsed incident_id as Int: \(intID) -> \(incidentID)")
                    #endif
                } else if let stringID = incidentData["incident_id"] as? String {
                    incidentID = stringID
                    #if DEBUG
                    print("Parsed incident_id as String: \(stringID)")
                    #endif
                } else {
                    if let altID = incidentData["id"] as? Int {
                        incidentID = String(altID)
                        #if DEBUG
                        print("Using 'id' field: \(altID)")
                        #endif
                    } else if let altStringID = incidentData["id"] as? String {
                        incidentID = altStringID
                        #if DEBUG
                        print("Using 'id' field as string: \(altStringID)")
                        #endif
                    } else {
                        incidentID = "unknown_\(index)"
                        #if DEBUG
                        print("No valid ID found, using: \(incidentID)")
                        #endif
                    }
                    #if DEBUG
                    print("Available keys in incident data: \(Array(incidentData.keys))")
                    #endif
                }
                let title = incidentData["title"] as? String ?? "Unknown"
                let deviceName = incidentData["name"] as? String
                let deviceIP = incidentData["ip"] as? String
                    ?? incidentData["device_ip"] as? String
                    ?? incidentData["ip_address"] as? String
                    ?? incidentData["ipaddress"] as? String
                    ?? incidentData["host_ip"] as? String
                let stateString = incidentData["incident_state"] as? String ?? "OPEN"

                let status: NetreoIncident.IncidentStatus
                if let forced = defaultStatus {
                    status = forced
                } else if stateString == "ACKNOWLEDGED" {
                    status = .acknowledged
                } else {
                    status = .active
                }

                // Netreo provides no severity field on this endpoint.
                // Read from known fields; fall back to .critical as the safe default
                // for active service-check failures.
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
                    let isoWithTZ = ISO8601DateFormatter()
                    isoWithTZ.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate,
                                               .withColonSeparatorInTime, .withTimeZone]
                    let isoLocal = ISO8601DateFormatter()
                    isoLocal.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate,
                                              .withColonSeparatorInTime]
                    isoLocal.timeZone = TimeZone.current
                    startTime = isoWithTZ.date(from: openTimeStr)
                        ?? isoLocal.date(from: openTimeStr)
                        ?? Date()
                } else {
                    startTime = Date()
                }
                
                let incident = NetreoIncident(
                    incidentID: incidentID,
                    deviceIP: deviceIP,
                    deviceName: deviceName,
                    summary: title,
                    description: nil,
                    severity: severity,
                    status: status,
                    incidentState: stateString,
                    category: "Network",
                    startTime: startTime
                )
                
                incidents.append(incident)
                #if DEBUG
                print("Successfully parsed incident \(incidentID)")
                #endif
            } catch {
                #if DEBUG
                print("Failed to parse incident \(index + 1): \(error)")
                #endif
                continue
            }
        }

        #if DEBUG
        print("Successfully parsed \(incidents.count) incidents")
        #endif
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
    
}

enum AlarmColor: String, CaseIterable, Hashable {
    case red, orange, yellow, green, blue, grey

    var color: Color {
        switch self {
        case .red:    return Color(red: 0.90, green: 0.15, blue: 0.10)
        case .orange: return Color(red: 0.95, green: 0.45, blue: 0.05)
        case .yellow: return Color(red: 0.97, green: 0.85, blue: 0.05)
        case .green:  return Color(red: 0.13, green: 0.55, blue: 0.13)
        case .blue:   return Color(red: 0.10, green: 0.40, blue: 0.85)
        case .grey:   return Color(.systemGray)
        }
    }

    // Mappt den "state"-Wert aus primary_alarm_log auf eine Farbe
    // Bekannte Werte: "WARNING", "CRITICAL", "MAJOR", "MINOR", "OK", "OPEN", "ACKNOWLEDGED"
    static func fromState(_ state: String?) -> AlarmColor {
        switch state?.uppercased() {
        case "CRITICAL", "DOWN":                                    return .red
        case "MAJOR", "UNREACHABLE":                                return .orange
        case "WARNING", "MINOR":                                    return .yellow
        case "OK", "RESOLVED", "CLOSED", "UP", "NORMAL",
             "RECOVERY", "CLEARED", "ALARMS CLEARED":              return .green
        case "ACKNOWLEDGED":                                        return .blue
        default:                                                    return .grey
        }
    }

    /// Severity rank: red (5) is worst, grey (0) is unknown/irrelevant
    var priority: Int {
        switch self {
        case .red:    return 5
        case .orange: return 4
        case .yellow: return 3
        case .blue:   return 2
        case .green:  return 1
        case .grey:   return 0
        }
    }

    /// Returns the highest-priority color that has count > 0; falls back to .green
    static func worst(from counts: [AlarmColor: Int]) -> AlarmColor {
        return counts
            .filter { $0.value > 0 }
            .max { $0.key.priority < $1.key.priority }
            .map { $0.key } ?? .green
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