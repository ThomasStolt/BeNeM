import Foundation

/// Resolves the best human-readable name for the active BHNM connection,
/// used as the toolbar subtitle on all four main screens.
///
/// Fallback chain (first non-empty wins):
/// 1. Saved connection whose id matches `activeConnectionID`
/// 2. Saved connection whose apiKey + middlewareURL match the active config
///    (covers legacy/migrated configs where the active ID was never set)
/// 3. The sole saved connection, if exactly one exists
/// 4. Host component of the BHNM URL
/// 5. Host component of the middleware URL
/// 6. "BeNeM" — guaranteed non-empty final fallback
func resolveActiveServerName(
    connections: [SavedConnection],
    activeConnectionID: String,
    middlewareURL: String,
    bhnmURL: String,
    apiKey: String
) -> String {
    if let byID = connections.first(where: { $0.id.uuidString == activeConnectionID }),
       !byID.name.isEmpty {
        return byID.name
    }
    if !apiKey.isEmpty,
       let byConfig = connections.first(where: {
           $0.apiKey == apiKey && $0.middlewareURL == middlewareURL
       }),
       !byConfig.name.isEmpty {
        return byConfig.name
    }
    if connections.count == 1, !connections[0].name.isEmpty {
        return connections[0].name
    }
    if let h = hostComponent(from: bhnmURL) { return h }
    if let h = hostComponent(from: middlewareURL) { return h }
    return "BeNeM"
}

/// Extracts the host (e.g. `bhnm.example.com`) from a possibly scheme-less
/// URL string. Returns nil for empty/unparseable input.
func hostComponent(from urlString: String) -> String? {
    let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
    guard let host = URLComponents(string: withScheme)?.host, !host.isEmpty else {
        return nil
    }
    return host
}
