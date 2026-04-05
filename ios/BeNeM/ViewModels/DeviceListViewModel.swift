import Foundation

@MainActor
class DeviceListViewModel: ObservableObject {
    @Published var devices: [NetreoDevice] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var totalRecords: Int = 0
    @Published var hasMore = false
    @Published var isLoadingMore = false

    // Search
    @Published var searchQuery: String = ""
    @Published var isSearching = false
    @Published var searchResults: [NetreoDevice] = []

    private var apiService: NetreoAPIService
    private let pageSize = 50

    var displayedDevices: [NetreoDevice] {
        searchQuery.count >= 2 ? searchResults : devices
    }

    init(apiService: NetreoAPIService) {
        self.apiService = apiService
    }

    func loadDevices() async {
        isLoading = true
        errorMessage = nil
        do {
            let page = try await apiService.fetchDevices(recordStart: 0, recordCount: pageSize)
            devices = page.devices
            totalRecords = page.totalRecords
            hasMore = page.devices.count < page.totalRecords
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadMoreDevices() async {
        guard hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        do {
            let page = try await apiService.fetchDevices(recordStart: devices.count, recordCount: pageSize)
            devices.append(contentsOf: page.devices)
            hasMore = devices.count < page.totalRecords
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingMore = false
    }

    func search(query: String) async {
        guard query.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }
        isSearching = true
        do {
            searchResults = try await apiService.searchDevices(query: query)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSearching = false
    }

    func updateAPIService(_ newService: NetreoAPIService) {
        apiService = newService
        devices = []
        searchResults = []
        searchQuery = ""
        Task { await loadDevices() }
    }
}
