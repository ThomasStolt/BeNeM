import Foundation

/// Shared in-memory cache for per-device threshold counts fetched from the middleware.
/// Refreshes at most once every 10 minutes. Thread-safe via @MainActor.
@MainActor
final class ThresholdCache: ObservableObject {
    static let shared = ThresholdCache()

    @Published private(set) var counts: [String: Int] = [:]
    private var lastFetched: Date? = nil
    private let staleDuration: TimeInterval = 600 // 10 minutes

    private init() {}

    /// Fetch fresh counts if the cache is empty or stale.
    func refresh(using service: NetreoAPIService) async {
        guard lastFetched == nil || Date().timeIntervalSince(lastFetched!) > staleDuration else { return }
        if let fresh = try? await service.fetchThresholdCounts() {
            counts = fresh
            lastFetched = Date()
        }
    }

    /// Threshold count for a given device name. Returns 0 if the device is not in the cache.
    /// Device name lookup is case-insensitive to match incident device names.
    func count(for deviceName: String) -> Int {
        let key = counts.keys.first { $0.caseInsensitiveCompare(deviceName) == .orderedSame }
        return key.flatMap { counts[$0] } ?? 0
    }

    /// Invalidate cache so the next refresh() call fetches fresh data.
    func invalidate() {
        lastFetched = nil
    }
}


/// Shared in-memory set of device names currently in maintenance, from the
/// middleware's maintenance-map cache. List-badge staleness is the map's
/// cache_age (worst case ~= middleware refresh + BHNM's ~85 s poll lag,
/// ~3.5 min at defaults); the Device Detail screen's live read stays the
/// fresher truth and may disagree for one cycle — accepted.
@MainActor
final class MaintenanceMapCache: ObservableObject {
    static let shared = MaintenanceMapCache()

    @Published private(set) var names: Set<String> = []
    private var lastFetched: Date? = nil
    private let staleDuration: TimeInterval = 60

    /// Creator-side optimism: after a successful create, the map chain lags
    /// (snap wait + BHNM poll + middleware cycle), so the creator's own
    /// device is noted locally and unioned into the set until the server
    /// catches up or the grace expires. Mirror of the detail pendingStart.
    private var localAdds: [String: Date] = [:]  // name -> expiry
    private let localGrace: TimeInterval = 8 * 60

    private init() {}

    func noteLocalMaintenance(_ deviceName: String) {
        localAdds[deviceName] = Date().addingTimeInterval(localGrace)
        names.insert(deviceName)
    }

    func clearLocalMaintenance(_ deviceName: String) {
        localAdds.removeValue(forKey: deviceName)
    }

    /// Fetch the fresh set if the cache is empty or stale. Failures keep the
    /// previous set (absent = no state shown, never a wrong one).
    func refresh(using service: NetreoAPIService) async {
        guard lastFetched == nil || Date().timeIntervalSince(lastFetched!) > staleDuration else { return }
        if let fresh = try? await service.fetchMaintenanceMap() {
            let now = Date()
            localAdds = localAdds.filter { $0.value > now }
            names = fresh.union(localAdds.keys)
            lastFetched = Date()
        }
    }

    func isInMaintenance(_ deviceName: String) -> Bool {
        names.contains(deviceName)
    }

    func invalidate() {
        lastFetched = nil
    }
}
