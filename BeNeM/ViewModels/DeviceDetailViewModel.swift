import Foundation

// MARK: - TimeFrame

enum TimeFrame: String, CaseIterable {
    case lastHour    = "Last Hour"
    case last2Hours  = "Last 2 Hours"
    case last5Hours  = "Last 5 Hours"
    case last24Hours = "Last 24 Hours"

    var displayName: String {
        switch self {
        case .lastHour:    return "1h"
        case .last2Hours:  return "2h"
        case .last5Hours:  return "5h"
        case .last24Hours: return "24h"
        }
    }
}

// MARK: - MetricCardState

struct MetricCardState {
    let instance: PerformanceInstance
    var isExpanded: Bool = false
    var isLoading: Bool = false
    var hasBeenFetched: Bool = false
    var data: [PerformanceDataPoint] = []
    var error: String? = nil

    var current: Double? { data.last?.value }
    var average: Double? {
        guard !data.isEmpty else { return nil }
        return data.map(\.value).reduce(0, +) / Double(data.count)
    }
    var max: Double? { data.map(\.value).max() }
}

// MARK: - DeviceDetailViewModel

@MainActor
class DeviceDetailViewModel: ObservableObject {
    @Published var incidents: [NetreoIncident] = []
    @Published var isLoadingIncidents = true
    @Published var incidentsError: String?

    @Published var categories: [PerformanceCategory] = []
    @Published var cardStates: [String: MetricCardState] = [:]
    @Published var isLoadingCategories = false
    @Published var categoriesError: String?

    @Published var healthyCount: Int = 0
    @Published var ackCount: Int = 0
    @Published var warningCount: Int = 0
    @Published var criticalCount: Int = 0

    private var devIndex: String?
    private let apiService: NetreoAPIService
    let device: NetreoDevice

    init(device: NetreoDevice, apiService: NetreoAPIService) {
        self.device = device
        self.apiService = apiService
    }

    func load() async {
        loadPinnedInterfaces()
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadIncidents() }
            group.addTask { await self.loadPerformanceStructure() }
        }
    }

    // MARK: - Pinned Interfaces

    @Published var pinnedKeys: [String] = []

    private var pinnedDefaultsKey: String {
        "pinned_interfaces_\(device.uid)"
    }

    func loadPinnedInterfaces() {
        pinnedKeys = UserDefaults.standard.stringArray(forKey: pinnedDefaultsKey) ?? []
    }

    func pinInterface(key: String) {
        guard !pinnedKeys.contains(key) else { return }
        pinnedKeys.append(key)
        UserDefaults.standard.set(pinnedKeys, forKey: pinnedDefaultsKey)
    }

    func unpinInterface(key: String) {
        pinnedKeys.removeAll { $0 == key }
        UserDefaults.standard.set(pinnedKeys, forKey: pinnedDefaultsKey)
    }

    func isInterfacePinned(key: String) -> Bool {
        pinnedKeys.contains(key)
    }

    // MARK: - Incidents

    private func loadIncidents() async {
        isLoadingIncidents = true
        incidentsError = nil
        do {
            let all = try await apiService.fetchIncidents()
            let deviceName = device.name
            incidents = all.filter { incident in
                let incName = incident.deviceName ?? ""
                let incIP   = incident.deviceIP   ?? ""
                return incName.caseInsensitiveCompare(deviceName) == .orderedSame
                    || incName.caseInsensitiveCompare(device.ip)  == .orderedSame
                    || incIP   == device.ip
                    || incName.lowercased().components(separatedBy: ".").first
                       == deviceName.lowercased().components(separatedBy: ".").first
            }
            // Compute alarm counts from incidents
            var healthy = 0, ack = 0, warn = 0, crit = 0
            for incident in incidents {
                if incident.status == .acknowledged {
                    ack += 1
                } else {
                    switch incident.severity {
                    case .critical, .major: crit += 1
                    case .warning, .minor:  warn += 1
                    case .informational: break
                    }
                }
            }
            if incidents.isEmpty { healthy = 1 }
            healthyCount = healthy
            ackCount = ack
            warningCount = warn
            criticalCount = crit
        } catch {
            incidentsError = error.localizedDescription
        }
        isLoadingIncidents = false
    }

    // MARK: - Performance Structure

    private func loadPerformanceStructure() async {
        isLoadingCategories = true
        categoriesError = nil
        let name = device.name

        guard let index = try? await apiService.findDeviceIndex(name: name) else {
            categoriesError = "Could not resolve device index for \"\(name)\""
            isLoadingCategories = false
            return
        }
        devIndex = index

        guard let cats = try? await apiService.fetchPerformanceCategories(deviceId: index),
              !cats.isEmpty else {
            categoriesError = "No performance categories found"
            isLoadingCategories = false
            return
        }
        categories = cats

        var allInstances: [PerformanceInstance] = []
        await withTaskGroup(of: [PerformanceInstance].self) { group in
            for cat in cats {
                group.addTask {
                    (try? await self.apiService.fetchPerformanceInstances(deviceId: index, category: cat)) ?? []
                }
            }
            for await instances in group {
                allInstances.append(contentsOf: instances)
            }
        }

        // Keep only useful instances: remove per-process, swap, raw-byte, and unsupported metrics
        allInstances = allInstances.filter { instance in
            let title = instance.title.lowercased()
            if title.contains("by process") { return false }
            if title.contains("swap") { return false }
            if instance.unit == "B" { return false }
            return true
        }

        var states: [String: MetricCardState] = [:]
        for instance in allInstances {
            states[instance.key] = MetricCardState(instance: instance)
        }
        cardStates = states
        isLoadingCategories = false

        // Auto-load Latency instances (fetch only, no expand)
        let latencyInstances = allInstances.filter { instance in
            cats.first(where: { $0.id == instance.categoryId })?.name.lowercased().contains("latency") == true
        }
        for instance in latencyInstances {
            Task { await self.fetchCard(instanceKey: instance.key) }
        }

        // Auto-load main utilization metrics for servers (fetch only, no expand)
        if device.typeClass.isServer {
            let serverKeywords = ["cpu", "memory", "disk"]
            for keyword in serverKeywords {
                guard let cat = cats.first(where: { $0.name.lowercased().contains(keyword) }) else { continue }
                let candidates = allInstances.filter { instance in
                    guard instance.categoryId == cat.id else { return false }
                    guard instance.unit == "%" else { return false }
                    let title = instance.title.lowercased()
                    if title.contains("core") || title.contains("voltage") { return false }
                    return true
                }
                // For disk: auto-load all partitions so we can pick the highest usage
                if keyword == "disk" {
                    for candidate in candidates {
                        Task { await self.fetchCard(instanceKey: candidate.key) }
                    }
                } else if let first = candidates.first {
                    Task { await self.fetchCard(instanceKey: first.key) }
                }
            }

        }
    }

    // MARK: - Latency

    var latencyStates: [MetricCardState] {
        let latencyCatIds = Set(categories.filter { $0.name.lowercased().contains("latency") }.map(\.id))
        return cardStates.values
            .filter { latencyCatIds.contains($0.instance.categoryId) }
            .sorted { $0.instance.key < $1.instance.key }
    }

    var serverUtilizationStates: [(category: PerformanceCategory, states: [MetricCardState])] {
        let orderedKeywords = ["cpu", "memory", "disk"]
        #if DEBUG
        var debugLines: [String] = ["categories: \(categories.map { "\($0.name)(\($0.id))" })"]
        for keyword in orderedKeywords {
            let cat = categories.first(where: { $0.name.lowercased().contains(keyword) })
            let matchingStates = cat.map { c in cardStates.values.filter { $0.instance.categoryId == c.id && $0.instance.unit == "%" } } ?? []
            debugLines.append("\(keyword): cat=\(cat?.name ?? "nil")(\(cat?.id ?? "nil")) states=\(matchingStates.count) fetched=\(matchingStates.filter(\.hasBeenFetched).count) withData=\(matchingStates.filter { !$0.data.isEmpty }.count)")
            for s in matchingStates.prefix(3) {
                debugLines.append("  \(s.instance.title) key=\(s.instance.key) descr=\(s.instance.instanceDescr ?? "nil") fetched=\(s.hasBeenFetched) data=\(s.data.count)")
            }
        }
        let debugPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("debug_server_util.txt")
        try? debugLines.joined(separator: "\n").data(using: .utf8)?.write(to: debugPath)
        #endif
        return orderedKeywords.compactMap { keyword in
            guard let cat = categories.first(where: { $0.name.lowercased().contains(keyword) }) else { return nil }
            let states = cardStates.values
                .filter { state in
                    guard state.instance.categoryId == cat.id else { return false }
                    guard state.instance.unit == "%" else { return false }
                    let title = state.instance.title.lowercased()
                    if title.contains("core") || title.contains("voltage") { return false }
                    return true
                }
                .sorted { $0.instance.key < $1.instance.key }
            // For disk: pick the partition with highest current usage
            if keyword == "disk" {
                let loaded = states.filter { $0.hasBeenFetched && !$0.data.isEmpty }
                if let highest = loaded.max(by: { ($0.current ?? 0) < ($1.current ?? 0) }) {
                    return (category: cat, states: [highest])
                }
                // Fallback to root "/" if data hasn't loaded yet
                if let root = states.first(where: { $0.instance.instanceDescr == "/" }) {
                    return (category: cat, states: [root])
                }
                // Still return first instance so placeholder can render
                if let first = states.first {
                    return (category: cat, states: [first])
                }
                return nil
            }
            // Take only the first instance per category
            let limited = Array(states.prefix(1))
            return limited.isEmpty ? nil : (category: cat, states: limited)
        }
    }

    /// CPU Core states (up to 4), sorted by key for consistent color assignment
    var cpuCoreStates: [MetricCardState] {
        let cpuCatIds = Set(categories.filter { $0.name.lowercased().contains("cpu") }.map(\.id))
        return cardStates.values
            .filter { state in
                cpuCatIds.contains(state.instance.categoryId)
                && state.instance.title.lowercased().contains("core")
                && state.instance.unit == "%"
            }
            .sorted { $0.instance.key < $1.instance.key }
            .prefix(4)
            .map { $0 }
    }

    var performanceMetricCount: Int {
        let latencyCatIds = Set(categories.filter { $0.name.lowercased().contains("latency") }.map(\.id))
        return cardStates.values.filter { !latencyCatIds.contains($0.instance.categoryId) }.count
    }

    // MARK: - Card Interactions

    /// Fetch data only (no expand) — used by auto-load for latency/utilization cards
    func fetchCard(instanceKey: String) async {
        guard let state = cardStates[instanceKey], !state.isLoading, !state.hasBeenFetched else { return }
        cardStates[instanceKey]?.isLoading = true
        do {
            let data = try await apiService.fetchTimeSeries(
                deviceName: device.name,
                instance: state.instance,
                timeFrame: .last24Hours
            )
            cardStates[instanceKey]?.data = data.filter { !$0.value.isNaN }
            cardStates[instanceKey]?.hasBeenFetched = true
            cardStates[instanceKey]?.isLoading = false
        } catch {
            cardStates[instanceKey]?.error = error.localizedDescription
            cardStates[instanceKey]?.hasBeenFetched = true
            cardStates[instanceKey]?.isLoading = false
        }
    }

    /// Retry a failed or empty metric fetch — resets state and re-fetches
    func retryCard(instanceKey: String) async {
        guard let state = cardStates[instanceKey], !state.isLoading else { return }
        cardStates[instanceKey]?.hasBeenFetched = false
        cardStates[instanceKey]?.error = nil
        cardStates[instanceKey]?.data = []
        await fetchCard(instanceKey: instanceKey)
    }

    /// Fetch all CPU core instances in a single API call and split the results.
    func fetchCpuCores(instanceKeys: [String]) async {
        let instances = instanceKeys.compactMap { cardStates[$0]?.instance }
        guard !instances.isEmpty else { return }

        // Mark all as loading
        for key in instanceKeys { cardStates[key]?.isLoading = true }

        do {
            let results = try await apiService.fetchTimeSeriesBatch(
                deviceName: device.name,
                instances: instances,
                timeFrame: .last24Hours
            )
            for key in instanceKeys {
                cardStates[key]?.data = (results[key] ?? []).filter { !$0.value.isNaN }
                cardStates[key]?.hasBeenFetched = true
                cardStates[key]?.isLoading = false
            }
        } catch {
            for key in instanceKeys {
                cardStates[key]?.error = error.localizedDescription
                cardStates[key]?.hasBeenFetched = true
                cardStates[key]?.isLoading = false
            }
        }
    }

    func tapCard(instanceKey: String) async {
        guard let state = cardStates[instanceKey] else { return }
        guard !state.isLoading else { return }

        if state.hasBeenFetched {
            cardStates[instanceKey]?.isExpanded.toggle()
            return
        }

        cardStates[instanceKey]?.isLoading = true
        let name = device.name
        do {
            let data = try await apiService.fetchTimeSeries(
                deviceName: name,
                instance: state.instance,
                timeFrame: .last24Hours
            )
            cardStates[instanceKey]?.data = data.filter { !$0.value.isNaN }
            cardStates[instanceKey]?.hasBeenFetched = true
            cardStates[instanceKey]?.isExpanded = true
            cardStates[instanceKey]?.isLoading = false
        } catch {
            cardStates[instanceKey]?.error = error.localizedDescription
            cardStates[instanceKey]?.hasBeenFetched = true
            cardStates[instanceKey]?.isLoading = false
        }
    }

}
