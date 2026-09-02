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
    /// Middleware-remembered scheduled starts (every user sees these).
    @Published private(set) var serverScheduled: [String: Date] = [:]
    private var lastFetched: Date? = nil
    private let staleDuration: TimeInterval = 60

    /// Creator-side local knowledge, shared so it survives navigation
    /// (screen state does not). Openly documented optimism: after a
    /// successful create the device is "pending" — list wrench blinks,
    /// detail button shows "Starts at HH:MM" — until the server map
    /// confirms (solid wrench / active button) or the note expires ~4 min
    /// past its start. A local close suppresses lagging server state ~3 min.
    private struct LocalNote {
        let startsAt: Date
        let expiry: Date
    }
    @Published private var localNotes: [String: LocalNote] = [:]
    @Published private var localCloses: [String: Date] = [:]  // name -> closedAt
    private let pendingGracePastStart: TimeInterval = 4 * 60
    private let closeGrace: TimeInterval = 3 * 60

    private init() {}

    func noteLocalMaintenance(_ deviceName: String, startsAt: Date) {
        localNotes[deviceName] = LocalNote(
            startsAt: startsAt,
            expiry: startsAt.addingTimeInterval(pendingGracePastStart)
        )
        localCloses.removeValue(forKey: deviceName)
    }

    func clearLocalMaintenance(_ deviceName: String) {
        localNotes.removeValue(forKey: deviceName)
    }

    /// Close/cancel: drop the pending note and suppress lagging server state.
    func noteLocalClose(_ deviceName: String) {
        localNotes.removeValue(forKey: deviceName)
        localCloses[deviceName] = Date()
    }

    func pendingStart(for deviceName: String) -> Date? {
        if let note = localNotes[deviceName], note.expiry > Date() {
            return note.startsAt
        }
        // Middleware-remembered schedule: another user's create, in sync.
        if let start = serverScheduled[deviceName],
           Date().timeIntervalSince(start) < pendingGracePastStart {
            return start
        }
        return nil
    }

    func recentLocalClose(for deviceName: String) -> Date? {
        guard let closedAt = localCloses[deviceName],
              Date().timeIntervalSince(closedAt) < closeGrace else { return nil }
        return closedAt
    }

    /// Server-confirmed or locally pending — drives whether the wrench shows.
    func isInMaintenance(_ deviceName: String) -> Bool {
        names.contains(deviceName) || pendingStart(for: deviceName) != nil
    }

    /// Locally noted but not yet server-confirmed — the wrench blinks.
    func isPending(_ deviceName: String) -> Bool {
        pendingStart(for: deviceName) != nil && !names.contains(deviceName)
    }

    /// Fetch the fresh set if the cache is empty or stale. Failures keep the
    /// previous set (absent = no state shown, never a wrong one).
    func refresh(using service: NetreoAPIService) async {
        guard lastFetched == nil || Date().timeIntervalSince(lastFetched!) > staleDuration else { return }
        if let fresh = try? await service.fetchMaintenanceMap() {
            let now = Date()
            localNotes = localNotes.filter { $0.value.expiry > now }
            localCloses = localCloses.filter { now.timeIntervalSince($0.value) < closeGrace }
            names = fresh.active  // server truth; pending is derived separately
            serverScheduled = fresh.scheduled
            lastFetched = Date()
        }
    }

    func invalidate() {
        lastFetched = nil
    }
}
