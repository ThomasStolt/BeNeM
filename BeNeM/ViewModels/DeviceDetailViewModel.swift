import Foundation

@MainActor
class DeviceDetailViewModel: ObservableObject {
    @Published var incidents: [NetreoIncident] = []
    @Published var cpuMetrics: [PerformanceMetric] = []
    @Published var memoryMetrics: [PerformanceMetric] = []
    @Published var diskMetrics: [PerformanceMetric] = []
    @Published var isLoadingIncidents = true
    @Published var isLoadingPerformance = true
    @Published var incidentsError: String?
    @Published var performanceError: String?

    private let apiService: NetreoAPIService
    let device: NetreoDevice

    init(device: NetreoDevice, apiService: NetreoAPIService) {
        self.device = device
        self.apiService = apiService
    }

    func load() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadIncidents() }
            group.addTask { await self.loadPerformance() }
        }
    }

    @MainActor private func loadIncidents() async {
        isLoadingIncidents = true
        incidentsError = nil
        do {
            let all = try await apiService.fetchIncidents()
            let deviceName = device.name ?? device.ip
            incidents = all.filter { incident in
                let incName = incident.deviceName ?? ""
                let incIP   = incident.deviceIP   ?? ""
                return incName.caseInsensitiveCompare(deviceName) == .orderedSame
                    || incName.caseInsensitiveCompare(device.ip)  == .orderedSame
                    || incIP   == device.ip
                    || incName.lowercased().components(separatedBy: ".").first == deviceName.lowercased().components(separatedBy: ".").first
            }
        } catch {
            incidentsError = error.localizedDescription
        }
        isLoadingIncidents = false
    }

    @MainActor private func loadPerformance() async {
        isLoadingPerformance = true
        performanceError = nil
        let name = device.name ?? device.ip
        do {
            async let cpu  = apiService.fetchPerformanceMetrics(deviceName: name, statGroup: "cpu",    units: "%")
            async let mem  = apiService.fetchPerformanceMetrics(deviceName: name, statGroup: "memory", units: "%")
            async let disk = apiService.fetchPerformanceMetrics(deviceName: name, statGroup: "disk",   units: "%")
            let (c, m, d) = try await (cpu, mem, disk)
            cpuMetrics    = c
            memoryMetrics = m
            diskMetrics   = d
        } catch {
            performanceError = error.localizedDescription
        }
        isLoadingPerformance = false
    }
}
