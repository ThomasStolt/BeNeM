import Foundation

/// In-memory ring buffer of the app's recent BHNM-via-middleware calls, shown in
/// the diagnostics screen (endpoint · status · ms). Not persisted. Callers pass a
/// clean logical endpoint name; `stripQuery` is a safety net so a raw URL (which
/// could carry a query string) never lands in the log.
@MainActor
final class ClientCallLog: ObservableObject {
    static let shared = ClientCallLog()

    struct Entry: Identifiable {
        let id = UUID()
        let endpoint: String
        let status: Int      // HTTP status code, or -1 for a transport failure
        let ms: Int
        let at: Date
    }

    @Published private(set) var entries: [Entry] = []
    private let cap = 20
    private init() {}

    func record(_ endpoint: String, status: Int, ms: Int) {
        entries.insert(Entry(endpoint: Self.stripQuery(endpoint), status: status, ms: ms, at: Date()), at: 0)
        if entries.count > cap { entries.removeLast(entries.count - cap) }
    }

    /// Drop any query string (defense-in-depth; logged names should already be clean).
    static func stripQuery(_ s: String) -> String {
        if let q = s.firstIndex(of: "?") { return String(s[..<q]) }
        return s
    }
}
