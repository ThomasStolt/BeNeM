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
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadIncidents() }
            group.addTask { await self.loadPerformanceStructure() }
        }
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

        // Keep only useful instances: remove per-process, swap, and raw-byte metrics
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

        // Auto-load Latency instances
        let latencyInstances = allInstances.filter { instance in
            cats.first(where: { $0.id == instance.categoryId })?.name.lowercased().contains("latency") == true
        }
        for instance in latencyInstances {
            Task { await self.tapCard(instanceKey: instance.key) }
        }
    }

    // MARK: - Card Interactions

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
            cardStates[instanceKey]?.data = data
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
