import Foundation
import SwiftUI

struct PerformanceCategory {
    let id: String
    let name: String
}

struct PerformanceInstance {
    let key: String           // unique; interface instances are suffixed "-in" or "-out"
    let title: String
    let unit: String          // unit sent to API (metricFilterUnits)
    let displayUnit: String   // unit shown in UI (may differ from API unit)
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
    private var categoryNameCache: [String: String]?
    private var siteNameCache: [String: String]?

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

    // MARK: - Category / Site Name Lookups

    private func ensureCategoryCache() async {
        guard categoryNameCache == nil else { return }
        categoryNameCache = [:]
        guard let url = URL(string: "\(configuration.baseURL)/fw/index.php?r=restful/category/list") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addProxyToken(&request)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [URLQueryItem(name: "password", value: configuration.apiKey)]
        if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
        request.httpBody = formEncodedBody(params)
        guard let (data, _) = try? await urlSession.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        for item in json {
            // SaaS BHNM returns id as Int; on-prem returns it as String
            let id = (item["id"] as? String) ?? (item["id"] as? Int).map(String.init) ?? ""
            if let name = item["name"] as? String, !id.isEmpty {
                categoryNameCache?[id] = name
            }
        }
    }

    private func ensureSiteCache() async {
        guard siteNameCache == nil else { return }
        siteNameCache = [:]
        guard let url = URL(string: "\(configuration.baseURL)/fw/index.php?r=restful/site/list") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addProxyToken(&request)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [URLQueryItem(name: "password", value: configuration.apiKey)]
        if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
        request.httpBody = formEncodedBody(params)
        guard let (data, _) = try? await urlSession.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        for item in json {
            // SaaS BHNM returns id as Int; on-prem returns it as String
            let id = (item["id"] as? String) ?? (item["id"] as? Int).map(String.init) ?? ""
            if let name = item["name"] as? String, !id.isEmpty {
                siteNameCache?[id] = name
            }
        }
    }

    private func resolveCategoryName(_ idOrName: String) -> String {
        if let name = categoryNameCache?[idOrName] { return name }
        return idOrName
    }

    private func resolveSiteName(_ idOrName: String) -> String {
        if let name = siteNameCache?[idOrName] { return name }
        return idOrName
    }

    struct DevicePage {
        let devices: [NetreoDevice]
        let totalRecords: Int
    }

    func fetchDevices(recordStart: Int = 0, recordCount: Int = 50) async throws -> DevicePage {
        await ensureCategoryCache()
        await ensureSiteCache()
        guard let url = URL(string: "\(configuration.baseURL)/fw/index.php?r=restful/devices/list") else {
            return DevicePage(devices: [], totalRecords: 0)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addProxyToken(&request)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [URLQueryItem(name: "password", value: configuration.apiKey)]
        if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
        params.append(URLQueryItem(name: "recordStart", value: String(recordStart)))
        params.append(URLQueryItem(name: "recordCount", value: String(recordCount)))
        request.httpBody = formEncodedBody(params)
        let (data, _) = try await urlSession.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return DevicePage(devices: [], totalRecords: 0)
        }
        let devicesArray: [[String: Any]]
        if let arr = json["devices"] as? [[String: Any]] {
            devicesArray = arr
        } else if let nested = json["data"] as? [String: Any],
                  let arr = nested["devices"] as? [[String: Any]] {
            devicesArray = arr
        } else {
            return DevicePage(devices: [], totalRecords: 0)
        }
        // totalRecords comes as String from API, displayRecords as Int
        let total: Int
        if let t = json["totalRecords"] as? Int { total = t }
        else if let t = json["totalRecords"] as? String, let n = Int(t) { total = n }
        else { total = devicesArray.count }

        #if DEBUG
        if let first = devicesArray.first {
            let debugLines = first.map { "\($0.key) = \($0.value)" }.sorted()
            UserDefaults.standard.set(debugLines.joined(separator: "\n"), forKey: "debug_device_fields")
        }
        #endif
        return DevicePage(devices: devicesArray.compactMap { parseDevice(from: $0) }, totalRecords: total)
    }

    func searchDevices(query: String) async throws -> [NetreoDevice] {
        await ensureCategoryCache()
        await ensureSiteCache()
        guard let url = URL(string: "\(configuration.baseURL)/fw/index.php?r=restful/devices/find") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addProxyToken(&request)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [
            URLQueryItem(name: "password", value: configuration.apiKey),
            URLQueryItem(name: "name", value: query),
        ]
        if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
        request.httpBody = formEncodedBody(params)
        let (data, _) = try await urlSession.data(for: request)
        // Response is a plain array, or a string error
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { parseDevice(from: $0) }
    }

    func fetchDevicesForCategory(categoryId: String) async throws -> [NetreoDevice] {
        await ensureCategoryCache()
        await ensureSiteCache()
        guard let url = URL(string: "\(configuration.baseURL)/fw/index.php?r=restful/category/device-list") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addProxyToken(&request)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [
            URLQueryItem(name: "password", value: configuration.apiKey),
            URLQueryItem(name: "id", value: categoryId),
        ]
        if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
        request.httpBody = formEncodedBody(params)
        let (data, _) = try await urlSession.data(for: request)
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { parseDevice(from: $0) }
    }

    func fetchDevicesForSite(siteId: String) async throws -> [NetreoDevice] {
        await ensureCategoryCache()
        await ensureSiteCache()
        guard let url = URL(string: "\(configuration.baseURL)/fw/index.php?r=restful/site/device-list") else { return [] }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addProxyToken(&request)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [
            URLQueryItem(name: "password", value: configuration.apiKey),
            URLQueryItem(name: "id", value: siteId),
        ]
        if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
        request.httpBody = formEncodedBody(params)
        let (data, _) = try await urlSession.data(for: request)
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { parseDevice(from: $0) }
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
        // SaaS BHNM returns dev_index as Int; on-prem returns String
        return (first["dev_index"] as? String) ?? (first["dev_index"] as? Int).map(String.init)
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
            let instanceType = dict["type"] as? String ?? ""

            if instanceType == "interface" {
                // Interface entries produce two instances: inbound and outbound
                // The "-in"/"-out" suffix is REQUIRED to ensure cardStates dictionary keys are unique
                let description = dict["description"] as? String ?? rawKey
                let bwUnit = (dict["bandwidth"] as? [String: Any])?["unit"] as? String ?? "%"
                instances.append(PerformanceInstance(
                    key: "\(rawKey)-in",
                    title: "\(description) — In",
                    unit: bwUnit,
                    displayUnit: bwUnit,
                    statGroup: category.name,
                    categoryId: category.id,
                    valueKey: "value1",
                    instanceDescr: description
                ))
                instances.append(PerformanceInstance(
                    key: "\(rawKey)-out",
                    title: "\(description) — Out",
                    unit: bwUnit,
                    displayUnit: bwUnit,
                    statGroup: category.name,
                    categoryId: category.id,
                    valueKey: "value2",
                    instanceDescr: description
                ))
            } else if instanceType == "oid_pertable" {
                let title = dict["title"] as? String ?? rawKey
                let unit  = dict["unit"]  as? String ?? ""
                let description = dict["description"] as? String ?? rawKey
                instances.append(PerformanceInstance(
                    key: "\(rawKey)-\(description)",
                    title: "\(title) (\(description))",
                    unit: unit,
                    displayUnit: unit,
                    statGroup: category.name,
                    categoryId: category.id,
                    valueKey: "value1",
                    instanceDescr: description
                ))
            } else {
                let title = dict["title"] as? String ?? rawKey
                let unit  = dict["unit"]  as? String ?? ""
                let description = dict["description"] as? String
                instances.append(PerformanceInstance(
                    key: rawKey,
                    title: title,
                    unit: unit,
                    displayUnit: unit,
                    statGroup: category.name,
                    categoryId: category.id,
                    valueKey: "value1",
                    instanceDescr: description
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
        let urlString = "\(configuration.baseURL)/fw/index.php?r=restful/devices/timeseries-metrics"
        guard let url = URL(string: urlString) else { return [] }

        // Use the real unit symbol when available (%, Volt, Seconds, etc.)
        // For empty-unit metrics, use the title — except known overrides where
        // the API expects a different value than the title
        let emptyUnitOverrides = ["Running Processes": "Processes"]
        let apiUnit = instance.unit.isEmpty
            ? (emptyUnitOverrides[instance.title] ?? instance.title)
            : instance.unit

        let boundary = "Boundary-\(UUID().uuidString)"
        var bodyData = Data()
        let fields: [(String, String)] = [
            ("password",               configuration.apiKey),
            ("groupFilterBy",          "device"),
            ("groupFilterValue",       deviceName),
            ("metricFilterStatGroup",  instance.statGroup),
            ("metricFilterUnits",      apiUnit),
            ("timeFrameFilterBy",      "time_offset"),
            ("timeFrameFilterValue",   timeFrame.rawValue),
            ("returnFormatFilterBy",   "average"),
        ] + (configuration.pin.map { [("pin", $0)] } ?? [])

        for (name, value) in fields {
            bodyData.append("--\(boundary)\r\n".data(using: .utf8)!)
            bodyData.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            bodyData.append("\(value)\r\n".data(using: .utf8)!)
        }
        bodyData.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addProxyToken(&request)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let (data, _) = try await urlSession.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let metrics = json["metrics"] as? [[String: Any]] else { return [] }

        // instanceDescr format on timeseries-metrics:
        //   oid:          "CPU Utilization for raspi-054 (CPU Utilization)"
        //   oid_pertable: "Memory Utilization on Physical memory (Used Space)"
        //   oid_pertable: "Disk Utilization on / (Percent Used Space)"
        //   interface:    varies — contains the interface description
        var points: [PerformanceDataPoint] = []
        #if DEBUG
        var debugFilterLog: [String] = []
        #endif
        for metric in metrics {
            if let filter = instance.instanceDescr {
                let descr = metric["instanceDescr"] as? String ?? ""
                // New endpoint uses "Title on <instanceDescr> (detail)" format
                // Extract the part between " on " and " (" for exact matching
                if let onRange = descr.range(of: " on "),
                   let parenRange = descr.range(of: " (", range: onRange.upperBound..<descr.endIndex) {
                    let extracted = String(descr[onRange.upperBound..<parenRange.lowerBound])
                    #if DEBUG
                    debugFilterLog.append("descr='\(descr)' extracted='\(extracted)' filter='\(filter)' match=\(extracted == filter)")
                    #endif
                    guard extracted == filter else { continue }
                } else {
                    #if DEBUG
                    debugFilterLog.append("descr='\(descr)' fallback contains=\(descr.localizedCaseInsensitiveContains(filter)) filter='\(filter)'")
                    #endif
                    // Fallback: check if descr contains filter (for oid types: "X for device (title)")
                    guard descr.localizedCaseInsensitiveContains(filter) else { continue }
                }
            }
            guard let datapoints = metric["datapoints"] as? [[String: Any]] else { continue }
            for bucket in datapoints {
                for (tsKey, rawValue) in bucket {
                    guard let ts = Double(tsKey) else { continue }
                    let value: Double?
                    if let s = rawValue as? String { value = Double(s) }
                    else if let d = rawValue as? Double { value = d }
                    else { value = nil }
                    guard let v = value else { continue }
                    points.append(PerformanceDataPoint(timestamp: Date(timeIntervalSince1970: ts), value: v))
                }
            }
        }
        #if DEBUG
        if instance.instanceDescr != nil {
            let safeTitle = instance.title.replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "/", with: "_")
            let safeDescr = instance.instanceDescr?.replacingOccurrences(of: "/", with: "_") ?? "nil"
            let debugPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                .appendingPathComponent("debug_filter_\(safeTitle)_\(safeDescr).txt")
            let info = "title: \(instance.title)\ninstanceDescr: \(instance.instanceDescr ?? "nil")\npoints: \(points.count)\nmetrics in response: \(metrics.count)\n\n\(debugFilterLog.joined(separator: "\n"))"
            try? info.data(using: .utf8)?.write(to: debugPath)
        }
        #endif
        return points.sorted { $0.timestamp < $1.timestamp }
    }

    /// Fetch time-series for a group of instances that share the same statGroup+unit in a single API call.
    /// Returns a dictionary keyed by instance key with the filtered data points for each.
    func fetchTimeSeriesBatch(
        deviceName: String,
        instances: [PerformanceInstance],
        timeFrame: TimeFrame
    ) async throws -> [String: [PerformanceDataPoint]] {
        guard let first = instances.first else { return [:] }

        let urlString = "\(configuration.baseURL)/fw/index.php?r=restful/devices/timeseries-metrics"
        guard let url = URL(string: urlString) else { return [:] }

        let emptyUnitOverrides = ["Running Processes": "Processes"]
        let apiUnit = first.unit.isEmpty
            ? (emptyUnitOverrides[first.title] ?? first.title)
            : first.unit

        let boundary = "Boundary-\(UUID().uuidString)"
        var bodyData = Data()
        let fields: [(String, String)] = [
            ("password",               configuration.apiKey),
            ("groupFilterBy",          "device"),
            ("groupFilterValue",       deviceName),
            ("metricFilterStatGroup",  first.statGroup),
            ("metricFilterUnits",      apiUnit),
            ("timeFrameFilterBy",      "time_offset"),
            ("timeFrameFilterValue",   timeFrame.rawValue),
            ("returnFormatFilterBy",   "average"),
        ] + (configuration.pin.map { [("pin", $0)] } ?? [])

        for (name, value) in fields {
            bodyData.append("--\(boundary)\r\n".data(using: .utf8)!)
            bodyData.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            bodyData.append("\(value)\r\n".data(using: .utf8)!)
        }
        bodyData.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addProxyToken(&request)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let (data, _) = try await urlSession.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let metrics = json["metrics"] as? [[String: Any]] else { return [:] }

        // Build a lookup: instanceDescr filter value → instance key
        var descrToKey: [String: String] = [:]
        for inst in instances {
            if let descr = inst.instanceDescr {
                descrToKey[descr] = inst.key
            }
        }

        var result: [String: [PerformanceDataPoint]] = [:]
        for inst in instances { result[inst.key] = [] }

        for metric in metrics {
            let descr = metric["instanceDescr"] as? String ?? ""
            // Extract the part between " on " and " (" to match against instance.instanceDescr
            var matchedKey: String?
            if let onRange = descr.range(of: " on "),
               let parenRange = descr.range(of: " (", range: onRange.upperBound..<descr.endIndex) {
                let extracted = String(descr[onRange.upperBound..<parenRange.lowerBound])
                matchedKey = descrToKey[extracted]
            }
            // Fallback: try contains match
            if matchedKey == nil {
                for (filter, key) in descrToKey {
                    if descr.localizedCaseInsensitiveContains(filter) {
                        matchedKey = key
                        break
                    }
                }
            }
            guard let key = matchedKey else { continue }

            guard let datapoints = metric["datapoints"] as? [[String: Any]] else { continue }
            for bucket in datapoints {
                for (tsKey, rawValue) in bucket {
                    guard let ts = Double(tsKey) else { continue }
                    let value: Double?
                    if let s = rawValue as? String { value = Double(s) }
                    else if let d = rawValue as? Double { value = d }
                    else { value = nil }
                    guard let v = value else { continue }
                    result[key, default: []].append(PerformanceDataPoint(timestamp: Date(timeIntervalSince1970: ts), value: v))
                }
            }
        }

        // Sort each series by timestamp
        for key in result.keys {
            result[key]?.sort { $0.timestamp < $1.timestamp }
        }


        return result
    }


    private func parseDevice(from dict: [String: Any]) -> NetreoDevice? {
        // UID is required — this is the primary identifier
        let uid: String
        if let u = dict["UID"] as? String { uid = u }
        else if let u = dict["UID"] as? Int { uid = String(u) }
        else { return nil }

        guard let ip = dict["ip"] as? String else { return nil }

        let guid = dict["GUID"] as? String ?? ""
        let devIndex = (dict["dev_index"] as? String) ?? (dict["dev_index"] as? Int).map(String.init) ?? ""
        let name = dict["name"] as? String ?? ip
        let description = dict["description"] as? String ?? ""
        // SaaS BHNM returns category, site, poll, monitor, create_time as integers
        let rawCategory = (dict["category"] as? String) ?? (dict["category"] as? Int).map(String.init) ?? ""
        let category = resolveCategoryName(rawCategory)
        let rawSite = (dict["site"] as? String) ?? (dict["site"] as? Int).map(String.init) ?? ""
        let site = resolveSiteName(rawSite)
        let model = dict["model"] as? String
        let serialNumber = dict["serial_number"] as? String
        let poll = (dict["poll"] as? String) == "1" || (dict["poll"] as? Int) == 1
        let monitor = (dict["monitor"] as? String) == "1" || (dict["monitor"] as? Int) == 1
        let snmpVersion = dict["snmp_version"] as? String
        let createTime = (dict["create_time"] as? String) ?? (dict["create_time"] as? Int).map(String.init)

        let status: NetreoDevice.DeviceStatus = {
            if let color = (dict["alarm_color"] as? String)?.lowercased() {
                switch color {
                case "red":    return .critical
                case "orange": return .warning
                case "yellow": return .warning
                case "green":  return .up
                default: break
                }
            }
            if let colorInt = dict["alarm_color"] as? Int {
                switch colorInt {
                case 3:  return .critical
                case 2:  return .warning
                case 1:  return .warning
                case 0:  return .up
                default: break
                }
            }
            if let colorStr = dict["alarm_color"] as? String, let colorInt = Int(colorStr) {
                switch colorInt {
                case 3:  return .critical
                case 2:  return .warning
                case 1:  return .warning
                case 0:  return .up
                default: break
                }
            }
            if let s = (dict["status"] as? String)?.lowercased() {
                switch s {
                case "critical", "down": return .critical
                case "warning":          return .warning
                case "up", "ok":         return .up
                default: break
                }
            }
            if let upStatus = dict["up_status"] as? Int {
                return upStatus == 1 ? .up : .down
            }
            return (poll && monitor) ? .up : .unknown
        }()

        return NetreoDevice(
            id: uid, uid: uid, guid: guid, devIndex: devIndex,
            name: name, ip: ip, description: description,
            category: category, site: site,
            model: (model?.isEmpty == true) ? nil : model,
            serialNumber: (serialNumber?.isEmpty == true) ? nil : serialNumber,
            poll: poll, monitor: monitor,
            snmpVersion: snmpVersion, createTime: createTime,
            status: status
        )
    }
    
    // MARK: - Tactical Group Summaries

    /// Single endpoint replacing all incident-derived summary logic.
    /// groupingType: "category" | "site" | "app" (business workflows)
    func fetchTacticalOverviewSummaries(groupingType: String) async throws -> [GroupSummary] {
        // Try cached endpoint first
        let cachedURL = "\(configuration.baseURL)/api/v1/tactical-overview?grouping_type=\(groupingType)"
        if let url = URL(string: cachedURL) {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            addProxyToken(&request)

            if let (data, response) = try? await urlSession.data(for: request),
               let httpResponse = response as? HTTPURLResponse,
               200...299 ~= httpResponse.statusCode,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Cached response wraps the BHNM data in a "data" key
                let tacticalData: [String: Any]
                if let wrapped = json["data"] as? [String: Any] {
                    tacticalData = wrapped
                } else {
                    // Fallthrough response is raw BHNM format
                    tacticalData = json
                }
                return parseTacticalOverview(tacticalData, groupingType: groupingType)
            }
        }

        // Fallback to direct BHNM call
        return try await fetchTacticalOverviewDirect(groupingType: groupingType)
    }

    private func fetchTacticalOverviewDirect(groupingType: String) async throws -> [GroupSummary] {
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
        return parseTacticalOverview(json, groupingType: groupingType)
    }

    private func parseTacticalOverview(_ json: [String: Any], groupingType: String) -> [GroupSummary] {
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

    /// Lightweight connection check via the HA status endpoint.
    /// Returns true if the server responds with a valid HA status JSON.
    func checkHAStatus() async -> Bool {
        guard let url = URL(string: "\(configuration.baseURL)/api/proxy/ha-status") else { return false }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        addProxyToken(&request)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [URLQueryItem(name: "password", value: configuration.apiKey)]
        if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
        request.httpBody = formEncodedBody(params)

        guard let (data, response) = try? await urlSession.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode,
              let raw = try? JSONSerialization.jsonObject(with: data) else {
            return false
        }
        // ha_status returns [{"role":"master","status":"1"}] or {"role":"standalone","status":"1"}
        let obj: [String: Any]?
        if let dict = raw as? [String: Any] { obj = dict }
        else if let arr = raw as? [[String: Any]] { obj = arr.first }
        else { obj = nil }
        return obj?["role"] as? String != nil
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
        let (data, response) = try await urlSession.data(for: request)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let success = json["success"] as? Bool, !success {
            return false
        }
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
        let (data, response) = try await urlSession.data(for: request)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let success = json["success"] as? Bool, !success {
            return false
        }
        return (response as? HTTPURLResponse)?.statusCode ?? 0 < 400
    }

    // MARK: - Maintenance Window

    func createMaintenanceWindow(deviceName: String, durationMinutes: Int, comment: String) async throws -> Bool {
        guard let url = URL(string: "\(configuration.baseURL)/api/proxy/maintenance/create") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addProxyToken(&request)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [
            URLQueryItem(name: "password", value: configuration.apiKey),
            URLQueryItem(name: "name", value: deviceName),
            URLQueryItem(name: "duration", value: String(durationMinutes)),
            URLQueryItem(name: "comment", value: comment),
        ]
        if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
        request.httpBody = formEncodedBody(params)
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        if httpResponse.statusCode >= 400 { return false }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let result = json["result"] as? String {
            return result == "completed"
        }
        return false
    }

    func fetchIncidentDetail(incidentID: String) async throws -> IncidentDetail? {
        guard let url = URL(string: "\(configuration.baseURL)/api/incident_api.php") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addProxyToken(&request)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [
            URLQueryItem(name: "pwd",         value: configuration.apiKey),
            URLQueryItem(name: "method",      value: "getincidentdetail"),
            URLQueryItem(name: "incident_id", value: incidentID)
        ]
        if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
        request.httpBody = formEncodedBody(params)
        let (data, _) = try await urlSession.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return IncidentDetail.parse(from: json)
    }

    /// Fetches incident detail and returns both the alert_type and alarm color counts.
    /// alert_type values from BHNM: "Host", "Service", "Threshold" (case-insensitive).
    private func fetchIncidentAlarmData(incidentID: String) async -> (alertType: String, counts: [AlarmColor: Int]) {
        guard let url = URL(string: "\(configuration.baseURL)/api/incident_api.php") else { return ("host", [:]) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addProxyToken(&request)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [
            URLQueryItem(name: "pwd",         value: configuration.apiKey),
            URLQueryItem(name: "method",      value: "getincidentdetail"),
            URLQueryItem(name: "incident_id", value: incidentID)
        ]
        if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
        request.httpBody = formEncodedBody(params)
        guard let (data, _) = try? await urlSession.data(for: request),
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
        return try await performLegacyIncidentRequest()
    }

    /// Fetches enriched incidents from the middleware cache endpoint.
    /// Returns (incidents, alarmCounts) — alarm_counts may be nil per incident if cache is cold.
    func fetchCachedIncidents() async throws -> ([NetreoIncident], [String: [AlarmColor: Int]]) {
        let urlString = "\(configuration.baseURL)/api/v1/incidents"
        #if DEBUG
        print("fetchCachedIncidents: URL = \(urlString)")
        print("fetchCachedIncidents: proxyToken = \(configuration.proxyToken.prefix(8))...")
        print("fetchCachedIncidents: bhnmURL = \(configuration.bhnmURL)")
        #endif
        guard let url = URL(string: urlString) else {
            throw APIError.configurationError("Invalid URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addProxyToken(&request)

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              200...299 ~= httpResponse.statusCode else {
            #if DEBUG
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "(nil)"
            print("fetchCachedIncidents: FAILED with status \(code), body: \(body.prefix(200))")
            #endif
            // Fall back to legacy if middleware doesn't support cached endpoint
            let incidents = try await fetchIncidents()
            return (incidents, [:])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }

        // If response is a proxied BHNM response (cache cold), it has no cache_age_seconds
        let isCached = json["cache_age_seconds"] != nil

        var incidents: [NetreoIncident] = []
        var alarmCounts: [String: [AlarmColor: Int]] = [:]

        if let activeArray = json["active_incidents"] as? [[String: Any]] {
            let parsed = try parseIncidentsFromNetreoFormat(from: activeArray, defaultStatus: nil)
            incidents.append(contentsOf: parsed)

            if isCached {
                for (i, raw) in activeArray.enumerated() where i < parsed.count {
                    if let counts = raw["alarm_counts"] as? [String: Any] {
                        alarmCounts[parsed[i].incidentID] = parseAlarmCounts(counts)
                    }
                }
            }
        }
        if let closedArray = json["closed_incidents"] as? [[String: Any]] {
            let parsed = try parseIncidentsFromNetreoFormat(from: closedArray, defaultStatus: .resolved)
            incidents.append(contentsOf: parsed)

            if isCached {
                for (i, raw) in closedArray.enumerated() where i < parsed.count {
                    if let counts = raw["alarm_counts"] as? [String: Any] {
                        alarmCounts[parsed[i].incidentID] = parseAlarmCounts(counts)
                    }
                }
            }
        }

        return (incidents, alarmCounts)
    }

    /// Convert {"red": 2, "orange": 1, ...} dict to [AlarmColor: Int]
    private func parseAlarmCounts(_ raw: [String: Any]) -> [AlarmColor: Int] {
        var result: [AlarmColor: Int] = [:]
        for (key, value) in raw {
            if let color = AlarmColor(rawValue: key), let intVal = value as? Int {
                result[color] = intVal
            }
        }
        return result
    }

    private func baseParameters() -> [String: Any] {
        var parameters: [String: Any] = ["pwd": configuration.apiKey]
        if let pin = configuration.pin {
            parameters["pin"] = pin
        }
        return parameters
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
        
        guard let url = URL(string: urlString) else {
            throw APIError.configurationError("Invalid server URL: \(urlString)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = endpoint.httpMethod(for: configuration.version).rawValue
        addProxyToken(&request)

        var comps = URLComponents()
        comps.queryItems = parameters.map { URLQueryItem(name: $0.key, value: "\($0.value)") }
        request.httpBody = comps.percentEncodedQuery?.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Retry once on networkConnectionLost using a fresh session — iOS URLSession
        // reuses pooled connections that the server has already closed (-1005).
        // A fresh session forces a new TCP connection rather than reusing the stale one.
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch let urlError as URLError where urlError.code == .networkConnectionLost {
            let freshConfig = URLSessionConfiguration.ephemeral
            freshConfig.timeoutIntervalForRequest = configuration.timeout
            let freshSession = URLSession(configuration: freshConfig)
            (data, response) = try await freshSession.data(for: request)
        }

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

    // MARK: - Threshold Cache

    /// Fetches pre-aggregated threshold counts per device from the middleware cache.
    /// Returns a dictionary mapping device name → threshold count.
    func fetchThresholdCounts() async throws -> [String: Int] {
        guard let url = URL(string: "\(configuration.baseURL)/api/v1/threshold-counts") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        addProxyToken(&request)
        let (data, response) = try await urlSession.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let countsDict = raw["counts"] as? [String: Any] else {
            return [:]
        }
        var result: [String: Int] = [:]
        for (key, value) in countsDict {
            if let intVal = value as? Int {
                result[key] = intVal
            } else if let numVal = value as? NSNumber {
                result[key] = numVal.intValue
            }
        }
        return result
    }

    /// Fetches the count of enabled + OK service checks for a device.
    func fetchDeviceServices(deviceName: String) async throws -> Int {
        guard let url = URL(string: "\(configuration.baseURL)/fw/index.php?r=restful/devices/services") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        addProxyToken(&request)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [
            URLQueryItem(name: "password", value: configuration.apiKey),
            URLQueryItem(name: "name",     value: deviceName)
        ]
        if let pin = configuration.pin { params.append(URLQueryItem(name: "pin", value: pin)) }
        request.httpBody = formEncodedBody(params)
        let (data, _) = try await urlSession.data(for: request)
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return 0
        }
        return raw.filter { item in
            let enabled = (item["enabled"] as? Bool) ?? ((item["enabled"] as? Int) == 1)
            let status  = (item["status"] as? String ?? "").lowercased()
            return enabled && (status == "ok" || status == "up")
        }.count
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