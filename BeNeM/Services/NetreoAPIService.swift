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
    
    private func formEncodedBody(_ params: [URLQueryItem]) -> Data? {
        var comps = URLComponents()
        comps.queryItems = params
        return comps.percentEncodedQuery?.data(using: .utf8)
    }

    func fetchDevices() async throws -> [NetreoDevice] {
        guard let url = URL(string: "\(configuration.baseURL)/fw/index.php?r=restful/devices/list") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
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

    func fetchCategorySummaries() async throws -> [GroupSummary] {
        async let devicesFetch   = fetchDevices()
        async let incidentsFetch = fetchIncidents()
        async let namesFetch     = fetchGroupNames(endpoint: "restful/category/list")
        let (devices, incidents, names) = try await (devicesFetch, incidentsFetch, namesFetch)
        let maps = await deviceStatusMap(devices: devices, incidents: incidents)
        return buildSummaries(devices: devices, hostStatusByIP: maps.hosts, serviceStatusByIP: maps.services, thresholdStatusByIP: maps.thresholds, keyPath: \.categoryID, names: names)
    }

    func fetchSiteSummaries() async throws -> [GroupSummary] {
        async let devicesFetch   = fetchDevices()
        async let incidentsFetch = fetchIncidents()
        async let namesFetch     = fetchGroupNames(endpoint: "restful/site/list")
        let (devices, incidents, names) = try await (devicesFetch, incidentsFetch, namesFetch)
        let maps = await deviceStatusMap(devices: devices, incidents: incidents)
        return buildSummaries(devices: devices, hostStatusByIP: maps.hosts, serviceStatusByIP: maps.services, thresholdStatusByIP: maps.thresholds, keyPath: \.siteID, names: names)
    }

    func fetchBusinessWorkflowSummaries() async throws -> [GroupSummary] {
        let groups = try await fetchStrategicGroupList()
        async let devicesFetch   = fetchDevices()
        async let incidentsFetch = fetchIncidents()
        let (devices, incidents) = try await (devicesFetch, incidentsFetch)
        let maps = await deviceStatusMap(devices: devices, incidents: incidents)
        let activeIPs = Set(devices.filter(\.isActive).map(\.ip))

        return try await withThrowingTaskGroup(of: GroupSummary?.self) { taskGroup in
            for sg in groups {
                taskGroup.addTask {
                    let memberIPs = (try? await self.fetchStrategicGroupMemberIPs(groupID: sg.id)) ?? []
                    var hG = 0, hB = 0, hY = 0, hO = 0, hR = 0
                    var sG = 0, sB = 0, sY = 0, sO = 0, sR = 0
                    var tG = 0, tB = 0, tY = 0, tO = 0, tR = 0
                    for ip in memberIPs where activeIPs.contains(ip) {
                        switch maps.hosts[ip] ?? .green {
                        case .green:  hG += 1
                        case .blue:   hB += 1
                        case .yellow: hY += 1
                        case .orange: hO += 1
                        case .red:    hR += 1
                        }
                        if let svc = maps.services[ip] {
                            switch svc { case .green: sG += 1; case .blue: sB += 1; case .yellow: sY += 1; case .orange: sO += 1; case .red: sR += 1 }
                        }
                        if let thr = maps.thresholds[ip] {
                            switch thr { case .green: tG += 1; case .blue: tB += 1; case .yellow: tY += 1; case .orange: tO += 1; case .red: tR += 1 }
                        }
                    }
                    let total = hG + hB + hY + hO + hR
                    guard total > 0 else { return nil }
                    return GroupSummary(id: sg.id, name: sg.name,
                                       hostsGreen: hG, hostsBlue: hB, hostsYellow: hY, hostsOrange: hO, hostsRed: hR,
                                       servicesGreen: sG, servicesBlue: sB, servicesYellow: sY, servicesOrange: sO, servicesRed: sR,
                                       thresholdsGreen: tG, thresholdsBlue: tB, thresholdsYellow: tY, thresholdsOrange: tO, thresholdsRed: tR)
                }
            }
            var result: [GroupSummary] = []
            for try await summary in taskGroup {
                if let s = summary { result.append(s) }
            }
            return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    // Overloads that accept pre-fetched data so the Dashboard can avoid redundant network calls.

    func fetchCategorySummaries(devices: [NetreoDevice], incidents: [NetreoIncident]) async throws -> [GroupSummary] {
        let names = try await fetchGroupNames(endpoint: "restful/category/list")
        let maps = await deviceStatusMap(devices: devices, incidents: incidents)
        return buildSummaries(devices: devices, hostStatusByIP: maps.hosts, serviceStatusByIP: maps.services, thresholdStatusByIP: maps.thresholds, keyPath: \.categoryID, names: names)
    }

    func fetchSiteSummaries(devices: [NetreoDevice], incidents: [NetreoIncident]) async throws -> [GroupSummary] {
        let names = try await fetchGroupNames(endpoint: "restful/site/list")
        let maps = await deviceStatusMap(devices: devices, incidents: incidents)
        return buildSummaries(devices: devices, hostStatusByIP: maps.hosts, serviceStatusByIP: maps.services, thresholdStatusByIP: maps.thresholds, keyPath: \.siteID, names: names)
    }

    func fetchBusinessWorkflowSummaries(devices: [NetreoDevice], incidents: [NetreoIncident]) async throws -> [GroupSummary] {
        let groups = try await fetchStrategicGroupList()
        let maps = await deviceStatusMap(devices: devices, incidents: incidents)
        let activeIPs = Set(devices.filter(\.isActive).map(\.ip))
        return try await withThrowingTaskGroup(of: GroupSummary?.self) { taskGroup in
            for sg in groups {
                taskGroup.addTask {
                    let memberIPs = (try? await self.fetchStrategicGroupMemberIPs(groupID: sg.id)) ?? []
                    var hG = 0, hB = 0, hY = 0, hO = 0, hR = 0
                    var sG = 0, sB = 0, sY = 0, sO = 0, sR = 0
                    var tG = 0, tB = 0, tY = 0, tO = 0, tR = 0
                    for ip in memberIPs where activeIPs.contains(ip) {
                        switch maps.hosts[ip] ?? .green {
                        case .green:  hG += 1
                        case .blue:   hB += 1
                        case .yellow: hY += 1
                        case .orange: hO += 1
                        case .red:    hR += 1
                        }
                        if let svc = maps.services[ip] {
                            switch svc { case .green: sG += 1; case .blue: sB += 1; case .yellow: sY += 1; case .orange: sO += 1; case .red: sR += 1 }
                        }
                        if let thr = maps.thresholds[ip] {
                            switch thr { case .green: tG += 1; case .blue: tB += 1; case .yellow: tY += 1; case .orange: tO += 1; case .red: tR += 1 }
                        }
                    }
                    let total = hG + hB + hY + hO + hR
                    guard total > 0 else { return nil }
                    return GroupSummary(id: sg.id, name: sg.name,
                                       hostsGreen: hG, hostsBlue: hB, hostsYellow: hY, hostsOrange: hO, hostsRed: hR,
                                       servicesGreen: sG, servicesBlue: sB, servicesYellow: sY, servicesOrange: sO, servicesRed: sR,
                                       thresholdsGreen: tG, thresholdsBlue: tB, thresholdsYellow: tY, thresholdsOrange: tO, thresholdsRed: tR)
                }
            }
            var result: [GroupSummary] = []
            for try await summary in taskGroup {
                if let s = summary { result.append(s) }
            }
            return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private func deviceStatusMap(devices: [NetreoDevice], incidents: [NetreoIncident])
        async -> (hosts: [String: HostAlarmStatus], services: [String: HostAlarmStatus], thresholds: [String: HostAlarmStatus]) {

        // Build a name → IP lookup (full name + base hostname for each device)
        var nameToIP: [String: String] = [:]
        for device in devices {
            let ip = device.ip
            for raw in [device.name, device.hostname].compactMap({ $0 }) {
                let lower = raw.lowercased()
                nameToIP[lower] = ip
                if let base = lower.components(separatedBy: ".").first, !base.isEmpty {
                    nameToIP[base] = ip
                }
            }
        }

        // Match active/acknowledged incidents to device IPs
        var incidentsByIP: [String: [NetreoIncident]] = [:]
        var unmatched: [String] = []
        for incident in incidents {
            guard incident.status == .active || incident.status == .acknowledged,
                  let rawName = incident.deviceName else { continue }
            let lower = rawName.lowercased()
            let base  = lower.components(separatedBy: ".").first ?? lower
            guard let ip = nameToIP[lower] ?? nameToIP[base] else {
                unmatched.append(rawName)
                continue
            }
            incidentsByIP[ip, default: []].append(incident)
        }
        #if DEBUG
        if unmatched.isEmpty {
            UserDefaults.standard.removeObject(forKey: "debug_unmatched_incidents")
        } else {
            UserDefaults.standard.set(unmatched.joined(separator: "\n"), forKey: "debug_unmatched_incidents")
        }
        #endif

        // Fetch alert_type + alarm counts for ALL incidents per IP in parallel
        var worstHostByIP: [String: AlarmColor] = [:]
        var worstServiceByIP: [String: AlarmColor] = [:]
        var worstThresholdByIP: [String: AlarmColor] = [:]

        await withTaskGroup(of: (String, String, AlarmColor).self) { group in
            for (ip, ipIncidents) in incidentsByIP {
                for incident in ipIncidents {
                    group.addTask {
                        let (alertType, counts) = await self.fetchIncidentAlarmData(incidentID: incident.incidentID)
                        return (ip, alertType, AlarmColor.worst(from: counts))
                    }
                }
            }
            for await (ip, alertType, color) in group {
                switch alertType {
                case "service":
                    let cur = worstServiceByIP[ip]
                    if cur == nil || color.priority > cur!.priority { worstServiceByIP[ip] = color }
                case "threshold":
                    let cur = worstThresholdByIP[ip]
                    if cur == nil || color.priority > cur!.priority { worstThresholdByIP[ip] = color }
                default: // "host" or anything else
                    let cur = worstHostByIP[ip]
                    if cur == nil || color.priority > cur!.priority { worstHostByIP[ip] = color }
                }
            }
        }

        // Host status for ALL active devices (green = no host incident)
        var hostResult: [String: HostAlarmStatus] = [:]
        for device in devices {
            switch worstHostByIP[device.ip] {
            case .red:               hostResult[device.ip] = .red
            case .orange:            hostResult[device.ip] = .orange
            case .yellow:            hostResult[device.ip] = .yellow
            case .blue:              hostResult[device.ip] = .blue
            case .green, .grey, nil: hostResult[device.ip] = .green
            }
        }

        // Service / threshold status for only devices that have incidents of that type
        func toStatus(_ color: AlarmColor) -> HostAlarmStatus {
            switch color {
            case .red:          return .red
            case .orange:       return .orange
            case .yellow:       return .yellow
            case .blue:         return .blue
            case .green, .grey: return .green
            }
        }
        let serviceResult   = worstServiceByIP.mapValues   { toStatus($0) }
        let thresholdResult = worstThresholdByIP.mapValues { toStatus($0) }

        return (hostResult, serviceResult, thresholdResult)
    }

    private struct SGInfo { let id: String; let name: String }

    // POST /fw/index.php?r=restful/strategic-group/list → direct JSON array
    private func fetchStrategicGroupList() async throws -> [SGInfo] {
        guard let url = URL(string: "\(configuration.baseURL)/fw/index.php?r=restful/strategic-group/list") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [URLQueryItem(name: "password", value: configuration.apiKey)]
        if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
        request.httpBody = formEncodedBody(params)
        let (data, _) = try await urlSession.data(for: request)
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { item -> SGInfo? in
            // Only include entries flagged as business workflows
            guard (item["business_workflow"] as? String) == "1" else { return nil }
            let id   = (item["id"]   as? String) ?? ""
            let name = (item["name"] as? String) ?? ""
            guard !id.isEmpty, !name.isEmpty else { return nil }
            return SGInfo(id: id, name: name)
        }
    }

    // POST /fw/index.php?r=restful/strategic-group/device-list with id=<groupID>
    private func fetchStrategicGroupMemberIPs(groupID: String) async throws -> [String] {
        guard let url = URL(string: "\(configuration.baseURL)/fw/index.php?r=restful/strategic-group/device-list") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [URLQueryItem(name: "password", value: configuration.apiKey), URLQueryItem(name: "id", value: groupID)]
        if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
        request.httpBody = formEncodedBody(params)
        let (data, _) = try await urlSession.data(for: request)
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { $0["ip"] as? String }
    }

    // Fetches id→name map — handles {"data":[…]}, {"data":{"items":[…]}}, or top-level [{…}]
    private func fetchGroupNames(endpoint: String) async throws -> [String: String] {
        guard let url = URL(string: "\(configuration.baseURL)/fw/index.php?r=\(endpoint)") else { return [:] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [URLQueryItem(name: "password", value: configuration.apiKey)]
        if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
        request.httpBody = formEncodedBody(params)
        let (data, _) = try await urlSession.data(for: request)

        // Collect items from whichever response shape the API uses
        var items: [[String: Any]] = []
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let arr = json["data"] as? [[String: Any]] {
                items = arr                                    // {"data":[…]}
            } else if let nested = json["data"] as? [String: Any] {
                for val in nested.values {
                    if let arr = val as? [[String: Any]] { items = arr; break }
                }
            } else {
                for key in ["categories", "sites", "groups", "items"] {
                    if let arr = json[key] as? [[String: Any]] { items = arr; break }
                }
            }
        } else if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            items = arr                                        // top-level array
        }

        var result: [String: String] = [:]
        for item in items {
            let id   = (item["id"]   as? String) ?? ""
            let name = (item["name"] as? String) ?? id
            if !id.isEmpty { result[id] = name }
        }
        return result
    }


    private func buildSummaries(devices: [NetreoDevice],
                                hostStatusByIP: [String: HostAlarmStatus],
                                serviceStatusByIP: [String: HostAlarmStatus],
                                thresholdStatusByIP: [String: HostAlarmStatus],
                                keyPath: KeyPath<NetreoDevice, String?>,
                                names: [String: String]) -> [GroupSummary] {
        struct Counts { var green = 0; var blue = 0; var yellow = 0; var orange = 0; var red = 0 }
        var hostBuckets: [String: (name: String, counts: Counts)] = [:]
        var serviceBuckets:   [String: Counts] = [:]
        var thresholdBuckets: [String: Counts] = [:]

        for device in devices {
            guard device.isActive else { continue }
            guard let key = device[keyPath: keyPath], !key.isEmpty else { continue }
            let displayName = names[key] ?? key

            // H — all active devices
            var hb = hostBuckets[key] ?? (name: displayName, counts: Counts())
            switch hostStatusByIP[device.ip] ?? .green {
            case .green:  hb.counts.green  += 1
            case .blue:   hb.counts.blue   += 1
            case .yellow: hb.counts.yellow += 1
            case .orange: hb.counts.orange += 1
            case .red:    hb.counts.red    += 1
            }
            hostBuckets[key] = hb

            // S — only devices with service incidents
            if let svc = serviceStatusByIP[device.ip] {
                var sb = serviceBuckets[key] ?? Counts()
                switch svc {
                case .green:  sb.green  += 1
                case .blue:   sb.blue   += 1
                case .yellow: sb.yellow += 1
                case .orange: sb.orange += 1
                case .red:    sb.red    += 1
                }
                serviceBuckets[key] = sb
            }

            // T — only devices with threshold incidents
            if let thr = thresholdStatusByIP[device.ip] {
                var tb = thresholdBuckets[key] ?? Counts()
                switch thr {
                case .green:  tb.green  += 1
                case .blue:   tb.blue   += 1
                case .yellow: tb.yellow += 1
                case .orange: tb.orange += 1
                case .red:    tb.red    += 1
                }
                thresholdBuckets[key] = tb
            }
        }

        return hostBuckets.compactMap { key, val -> GroupSummary? in
            let total = val.counts.green + val.counts.blue + val.counts.yellow + val.counts.orange + val.counts.red
            guard total > 0 else { return nil }
            let s = serviceBuckets[key]   ?? Counts()
            let t = thresholdBuckets[key] ?? Counts()
            return GroupSummary(
                id: key, name: val.name,
                hostsGreen:      val.counts.green,  hostsBlue:      val.counts.blue,
                hostsYellow:     val.counts.yellow, hostsOrange:    val.counts.orange,  hostsRed:      val.counts.red,
                servicesGreen:   s.green,           servicesBlue:   s.blue,
                servicesYellow:  s.yellow,          servicesOrange: s.orange,           servicesRed:   s.red,
                thresholdsGreen: t.green,           thresholdsBlue: t.blue,
                thresholdsYellow: t.yellow,         thresholdsOrange: t.orange,         thresholdsRed: t.red
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    func acknowledgeIncident(incidentID: String, user: String, comment: String = "Acked from Mobile App") async throws -> Bool {
        guard let url = URL(string: "\(configuration.baseURL)/fw/index.php?r=restful/incident/acknowledge") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
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
        #if DEBUG
        print("Fetching incidents from URL: \(urlString)")
        print("Parameters: \(parameters)")
        #endif
        
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
        
        #if DEBUG
        if let responseString = String(data: data, encoding: .utf8) {
            print("Raw incident API response: \(responseString)")
        }
        #endif
        
        // Try to parse response
        if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
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