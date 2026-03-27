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
    /// Incremented on each server switch; stale in-flight tasks compare before writing results.
    private var generation: Int = 0

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
        let myGeneration = generation
        isLoading = true
        errorMessage = nil
        do {
            let result = try await apiService.fetchTacticalOverviewSummaries(groupingType: type.groupingType)
            guard generation == myGeneration else { return }
            groups = result
        } catch is CancellationError {
            // Task cancelled by server switch — discard silently.
        } catch {
            guard generation == myGeneration else { return }
            errorMessage = error.localizedDescription
        }
        guard generation == myGeneration else { return }
        isLoading = false
    }

    func updateAPIService(_ newService: NetreoAPIService) {
        generation += 1
        apiService = newService
        groups = []
        isLoading = false
        Task { await load() }
    }

}
