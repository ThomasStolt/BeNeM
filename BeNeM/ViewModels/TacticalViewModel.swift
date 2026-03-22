import Foundation

@MainActor
class TacticalViewModel: ObservableObject {
    @Published var groups: [GroupSummary] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showAlarmsOnly = false

    var filteredGroups: [GroupSummary] {
        guard showAlarmsOnly else { return groups }
        return groups.filter { $0.hostsBlue + $0.hostsYellow + $0.hostsOrange + $0.hostsRed > 0 }
    }

    private let apiService: NetreoAPIService
    private let type: GroupType

    enum GroupType {
        case category, site, businessWorkflow
    }

    init(apiService: NetreoAPIService, type: GroupType) {
        self.apiService = apiService
        self.type = type
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            switch type {
            case .category:         groups = try await apiService.fetchCategorySummaries()
            case .site:             groups = try await apiService.fetchSiteSummaries()
            case .businessWorkflow: groups = try await apiService.fetchBusinessWorkflowSummaries()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadWith(preloadedDevices: [NetreoDevice], preloadedIncidents: [NetreoIncident]) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        do {
            switch type {
            case .category:
                groups = try await apiService.fetchCategorySummaries(devices: preloadedDevices, incidents: preloadedIncidents)
            case .site:
                groups = try await apiService.fetchSiteSummaries(devices: preloadedDevices, incidents: preloadedIncidents)
            case .businessWorkflow:
                groups = try await apiService.fetchBusinessWorkflowSummaries(devices: preloadedDevices, incidents: preloadedIncidents)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
