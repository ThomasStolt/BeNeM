import Foundation

@MainActor
class DeviceListViewModel: ObservableObject {
    @Published var devices: [NetreoDevice] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    @Published var hasMore = false
    @Published var isLoadingMore = false

    private var apiService: NetreoAPIService
    private var currentLimit: Int? = nil

    init(apiService: NetreoAPIService) {
        self.apiService = apiService
    }

    func loadDevices(limit: Int? = nil) async {
        if let limit { currentLimit = limit }
        isLoading = true
        errorMessage = nil
        do {
            let page = try await apiService.fetchDevicesPage(limit: currentLimit, offset: 0)
            devices = page
            hasMore = currentLimit.map { page.count >= $0 } ?? false
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func loadMoreDevices() async {
        guard let limit = currentLimit, hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        do {
            let page = try await apiService.fetchDevicesPage(limit: limit, offset: devices.count)
            devices.append(contentsOf: page)
            hasMore = page.count >= limit
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingMore = false
    }
    
    func addDevice(ip: String, snmpPublic: String, name: String? = nil) async {
        do {
            let success = try await apiService.addDevice(ip: ip, snmpPublic: snmpPublic, name: name)
            if success {
                await loadDevices()
            } else {
                errorMessage = "Failed to add device"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func deleteDevice(_ device: NetreoDevice) async {
        do {
            let success = try await apiService.deleteDevice(identifier: device.ip)
            if success {
                await loadDevices()
            } else {
                errorMessage = "Failed to delete device"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateAPIService(_ newService: NetreoAPIService) {
        apiService = newService
        Task { await loadDevices(limit: currentLimit) }
    }

    func renameDevice(_ device: NetreoDevice, newName: String) async {
        do {
            let success = try await apiService.renameDevice(identifier: device.ip, newName: newName)
            if success {
                await loadDevices()
            } else {
                errorMessage = "Failed to rename device"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}