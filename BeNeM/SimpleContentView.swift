import SwiftUI

struct SimpleContentView: View {
    @State private var serverIP = ""
    @State private var apiKey = ""
    @State private var devices: [SimpleDevice] = []
    @State private var isConnected = false
    @State private var netreoService: SimpleNetreoService?
    @State private var lastError: String?
    
    private let userDefaults = UserDefaults.standard
    
    var body: some View {
        TabView {
            if isConnected, let service = netreoService {
                SimpleDeviceListView(devices: devices, netreoService: service) {
                    await refreshDevices()
                }
                .tabItem {
                    Image(systemName: "network")
                    Text("Devices")
                }
            } else {
                welcomeView
                    .tabItem {
                        Image(systemName: "house")
                        Text("Home")
                    }
            }
            
            settingsView
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
        }
        .onAppear {
            loadConnectionSettings()
        }
    }
    
    private var welcomeView: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 30) {
                    VStack(spacing: 20) {
                        Image(systemName: "network")
                            .font(.system(size: 80))
                            .foregroundStyle(.tint)
                        
                        Text("Welcome to BeNeM")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("Network Management Client for Netreo")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    SimpleQuickConfigView(
                        serverIP: $serverIP,
                        apiKey: $apiKey,
                        onConnectionSuccess: { service, deviceList in
                            netreoService = service
                            devices = deviceList
                            isConnected = true
                            saveConnectionSettings()
                        }
                    )
                    
                    VStack(spacing: 12) {
                        Text("Getting Started:")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Enter your Netreo server IP address", systemImage: "1.circle.fill")
                            Label("Provide your API key from Netreo admin", systemImage: "2.circle.fill")
                            Label("Test the connection", systemImage: "3.circle.fill")
                            Label("Start monitoring your network devices", systemImage: "4.circle.fill")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("BeNeM")
        }
    }
    
    private var settingsView: some View {
        NavigationView {
            Form {
                Section(header: Text("Connection")) {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(isConnected ? "Connected" : "Not Connected")
                            .foregroundColor(isConnected ? .green : .red)
                    }
                    
                    if isConnected {
                        HStack {
                            Text("Server")
                            Spacer()
                            Text(serverIP)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Devices")
                            Spacer()
                            Text("\(devices.count)")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                if let error = lastError {
                    Section(header: Text("Last Error")) {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                
                if isConnected {
                    Section {
                        Button("Disconnect") {
                            disconnect()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
    
    private func refreshDevices() async {
        guard let service = netreoService else { return }
        
        do {
            let newDevices = try await service.fetchDevices()
            await MainActor.run {
                devices = newDevices
                lastError = nil
            }
        } catch {
            await MainActor.run {
                lastError = error.localizedDescription
            }
            print("Failed to refresh devices: \(error)")
        }
    }
    
    private func disconnect() {
        isConnected = false
        netreoService = nil
        devices = []
        serverIP = ""
        apiKey = ""
        clearConnectionSettings()
    }
    
    private func saveConnectionSettings() {
        userDefaults.set(serverIP, forKey: "netreo_server_ip")
        userDefaults.set(apiKey, forKey: "netreo_api_key")
        userDefaults.set(true, forKey: "netreo_connected")
    }
    
    private func loadConnectionSettings() {
        serverIP = userDefaults.string(forKey: "netreo_server_ip") ?? ""
        apiKey = userDefaults.string(forKey: "netreo_api_key") ?? ""
        let wasConnected = userDefaults.bool(forKey: "netreo_connected")
        
        if wasConnected && !serverIP.isEmpty && !apiKey.isEmpty {
            Task {
                await reconnectWithSavedSettings()
            }
        }
    }
    
    private func clearConnectionSettings() {
        userDefaults.removeObject(forKey: "netreo_server_ip")
        userDefaults.removeObject(forKey: "netreo_api_key")
        userDefaults.removeObject(forKey: "netreo_connected")
    }
    
    private func reconnectWithSavedSettings() async {
        do {
            let service = SimpleNetreoService(baseURL: formatURL(serverIP), apiKey: apiKey)
            let deviceList = try await service.testConnection()
            
            await MainActor.run {
                netreoService = service
                devices = deviceList
                isConnected = true
            }
        } catch {
            await MainActor.run {
                lastError = error.localizedDescription
                clearConnectionSettings()
            }
        }
    }
    
    private func formatURL(_ url: String) -> String {
        var formatted = url.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if !formatted.hasPrefix("http://") && !formatted.hasPrefix("https://") {
            formatted = "http://\(formatted)"
        }
        
        return formatted
    }
}

#Preview {
    SimpleContentView()
}