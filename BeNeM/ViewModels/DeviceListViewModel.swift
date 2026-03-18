import Foundation

@MainActor
class DeviceListViewModel: ObservableObject {
    @Published var devices: [NetreoDevice] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let apiService: NetreoAPIService
    
    init(apiService: NetreoAPIService) {
        self.apiService = apiService
    }
    
    func loadDevices() async {
        isLoading = true
        errorMessage = nil
        
        do {
            devices = try await apiService.fetchDevices()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
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