import Foundation

@MainActor
class TacticalViewModel: ObservableObject {
    @Published var groups: [GroupSummary] = [] { didSet { applyFilter() } }
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showAlarmsOnly = false { didSet { applyFilter() } }
    @Published var filteredGroups: [GroupSummary] = []

    private func applyFilter() {
        filteredGroups = showAlarmsOnly
            ? groups.filter { $0.hasAlarms }
            : groups
    }

    private var apiService: NetreoAPIService
    private let type: GroupType

    enum GroupType {
        case category, site, businessWorkflow

        var groupingType: String {
            switch self {
            case .category:         return "category"
            case .site:             return "site"
            case .businessWorkflow: return "app"
            }
        }
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
            groups = try await apiService.fetchTacticalOverviewSummaries(groupingType: type.groupingType)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func updateAPIService(_ newService: NetreoAPIService) {
        apiService = newService
        groups = []
        Task { await load() }
    }

}
