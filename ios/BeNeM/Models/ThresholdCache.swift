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
    func count(for deviceName: String) -> Int {
        counts[deviceName] ?? 0
    }

    /// Invalidate cache so the next refresh() call fetches fresh data.
    func invalidate() {
        lastFetched = nil
    }
}
