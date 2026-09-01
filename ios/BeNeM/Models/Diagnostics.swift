import Foundation

/// Decoded payload of the middleware's `GET /api/v1/diagnostics`.
/// Counts / booleans / timestamps / latency + scrubbed error strings only — the
/// middleware guarantees no secrets in this payload.
struct Diagnostics: Decodable {
    let middleware: Middleware
    let server: Server

    struct Middleware: Decodable {
        let version: String?
        let registered_devices: Int?
        let server_time: Int?
    }

    struct Server: Decodable {
        let name: String?
        let host: String?
        let cache_enabled: Bool?
        let bhnm: Bhnm
        let feeds: [String: Feed]
    }

    struct Bhnm: Decodable {
        let reachable: Bool?         // nil = monitor has no verdict yet (startup window)
        let source: String?          // "monitor" | "none" | "error"
        let latency_ms: Int?
        let last_success_age_seconds: Int?
        let last_error: String?
        let last_error_age_seconds: Int?
        let consecutive_failures: Int?
    }

    struct Feed: Decodable {
        let cached: Bool?
        let age_seconds: Int?
        let count: Int?
        let consecutive_failures: Int?
        let last_error: String?
    }
}

/// Result of a diagnostics fetch: the decoded payload plus the client-measured
/// App→Middleware round-trip and whether the middleware was reached at all.
struct DiagnosticsResult {
    let diagnostics: Diagnostics?
    let appToMiddlewareMs: Int?
    let reachedMiddleware: Bool

    /// A response counts as "reached the middleware" only when the middleware
    /// app itself answered (2xx). A reverse proxy (Caddy) answering 502/503 for
    /// a dead app container is NOT the middleware — that state must show the
    /// middleware-down banner, not sit in amber "checking" forever.
    static func reachedMiddleware(statusCode: Int) -> Bool {
        (200..<300).contains(statusCode)
    }
}
