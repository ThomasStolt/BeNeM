import Foundation

struct NetreoAPIConfiguration {
    /// Always the middleware URL. There is no direct-to-BHNM mode: `ContentView`
    /// is the only place that builds this and always passes the middleware, the
    /// add/edit form refuses to save without one (`ServerDraft.saveDisabled`), and
    /// every request carries `X-Proxy-Token`. A comment here used to claim
    /// "= bhnmURL for direct connections"; no code ever did that.
    let baseURL: String
    let bhnmURL: String       // the BHNM target, sent as X-BHNM-Target
    let apiKey: String
    let pin: String?
    let proxyToken: String
    /// Governs `URLSessionConfiguration` only. Two call sites set their own and
    /// ignore this: the diagnostics read (10 s) and the save probe (15 s).
    let timeout: TimeInterval

    init(baseURL: String, bhnmURL: String = "", apiKey: String, pin: String? = nil,
         proxyToken: String = "", timeout: TimeInterval = 30) {
        let normalizedURL = baseURL.trimmingSuffix("/")

        // Ensure URL has protocol
        if !normalizedURL.hasPrefix("http://") && !normalizedURL.hasPrefix("https://") {
            self.baseURL = "http://\(normalizedURL)"
        } else {
            self.baseURL = normalizedURL
        }

        self.bhnmURL    = bhnmURL
        self.apiKey     = apiKey
        self.pin        = pin
        self.proxyToken = proxyToken
        self.timeout    = timeout
    }
    
    func endpoint(for path: String) -> String {
        return "\(baseURL)\(path.hasPrefix("/") ? path : "/\(path)")"
    }
}

enum NetreoEndpoint {
    case deviceList
    case deviceAdd
    case deviceDelete(String)
    case deviceInfo(String)
    case deviceRename(String, String)
    case devicePerformance(String)
    case deviceServices(String)
    case incidents
    case acknowledgment
    case categories
    case sites
    case custom(String)
    
    /// Legacy (PHP) paths, unconditionally. The v1/v2/openapi variants were
    /// selectable from Settings until 2.13.3 and never worked: the middleware
    /// proxies BHNM's own endpoints, so `/api/v1/incidents` had nothing serving
    /// it, and only this one call site ever consulted the setting — the other
    /// fifteen hardcode `/fw/index.php?r=restful/...`. Picking anything but
    /// legacy silently broke device-detail incidents and nothing else.
    var legacyPath: String {
        switch self {
        case .deviceList:                 return "/devices/list"
        case .deviceAdd:                  return "/new_device_api.php"
        case .deviceDelete:               return "/device_delete_api.php"
        case .deviceInfo:                 return "/device_info_api.php"
        case .deviceRename:               return "/device_rename_api.php"
        case .devicePerformance:          return "/devices/performance-category"
        case .deviceServices:             return "/devices/services"
        case .incidents:                  return "/api/incident_api.php"
        case .acknowledgment:             return "/incident_ack.php"
        case .categories:                 return "/categories"
        case .sites:                      return "/sites"
        case .custom(let path):           return path
        }
    }

    var legacyHTTPMethod: HTTPMethod {
        switch self {
        case .deviceList, .deviceInfo, .devicePerformance, .deviceServices,
             .incidents, .categories, .sites, .deviceAdd, .deviceDelete,
             .deviceRename, .acknowledgment:
            return .POST
        case .custom:
            return .GET
        }
    }
}

enum HTTPMethod: String {
    case GET = "GET"
    case POST = "POST"
    case PUT = "PUT"
    case PATCH = "PATCH"
    case DELETE = "DELETE"
}

extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        return hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}