import Foundation

struct NetreoAPIConfiguration {
    let baseURL: String
    let apiKey: String
    let pin: String?
    let proxyToken: String
    let version: APIVersion
    let timeout: TimeInterval
    let retryCount: Int
    
    enum APIVersion: String, CaseIterable {
        case legacy = "legacy"
        case v1 = "v1"
        case v2 = "v2"
        case openapi = "openapi"
        
        var endpointPrefix: String {
            switch self {
            case .legacy:
                return ""
            case .v1:
                return "/api/v1"
            case .v2:
                return "/api/v2"
            case .openapi:
                return "/api"
            }
        }
    }
    
    init(baseURL: String, apiKey: String, pin: String? = nil, proxyToken: String = "", version: APIVersion = .legacy, timeout: TimeInterval = 30, retryCount: Int = 3) {
        let normalizedURL = baseURL.trimmingSuffix("/")
        
        // Ensure URL has protocol
        if !normalizedURL.hasPrefix("http://") && !normalizedURL.hasPrefix("https://") {
            self.baseURL = "http://\(normalizedURL)"
        } else {
            self.baseURL = normalizedURL
        }
        
        self.apiKey = apiKey
        self.pin = pin
        self.proxyToken = proxyToken
        self.version = version
        self.timeout = timeout
        self.retryCount = retryCount
    }
    
    func endpoint(for path: String) -> String {
        return "\(baseURL)\(version.endpointPrefix)\(path.hasPrefix("/") ? path : "/\(path)")"
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
    
    func path(for version: NetreoAPIConfiguration.APIVersion) -> String {
        switch self {
        case .deviceList:
            return version == .legacy ? "/devices/list" : "/devices"
        case .deviceAdd:
            return version == .legacy ? "/new_device_api.php" : "/devices"
        case .deviceDelete(let identifier):
            return version == .legacy ? "/device_delete_api.php" : "/devices/\(identifier)"
        case .deviceInfo(let identifier):
            return version == .legacy ? "/device_info_api.php" : "/devices/\(identifier)"
        case .deviceRename(let identifier, _):
            return version == .legacy ? "/device_rename_api.php" : "/devices/\(identifier)/rename"
        case .devicePerformance(let identifier):
            return version == .legacy ? "/devices/performance-category" : "/devices/\(identifier)/performance"
        case .deviceServices(let identifier):
            return version == .legacy ? "/devices/services" : "/devices/\(identifier)/services"
        case .incidents:
            return version == .legacy ? "/api/incident_api.php" : "/incidents"
        case .acknowledgment:
            return version == .legacy ? "/incident_ack.php" : "/incidents/acknowledge"
        case .categories:
            return version == .legacy ? "/categories" : "/categories"
        case .sites:
            return version == .legacy ? "/sites" : "/sites"
        case .custom(let path):
            return path
        }
    }
    
    func httpMethod(for version: NetreoAPIConfiguration.APIVersion) -> HTTPMethod {
        switch self {
        case .deviceList, .deviceInfo, .devicePerformance, .deviceServices, .incidents, .categories, .sites:
            return version == .legacy ? .POST : .GET
        case .deviceAdd:
            return .POST
        case .deviceDelete:
            return version == .legacy ? .POST : .DELETE
        case .deviceRename:
            return version == .legacy ? .POST : .PATCH
        case .acknowledgment:
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