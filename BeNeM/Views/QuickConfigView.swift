import SwiftUI

struct QuickConfigView: View {
    @AppStorage("netreo_base_url") private var baseURL = ""
    @AppStorage("netreo_api_key") private var apiKey = ""
    @AppStorage("netreo_pin") private var pin = ""
    @AppStorage("netreo_api_version") private var apiVersionString = "legacy"
    
    @State private var showingFullSettings = false
    @State private var isTestingConnection = false
    @State private var connectionResult: String?
    @State private var showingAlert = false
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Quick Setup")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                TextField("Netreo Server IP (e.g., 192.168.2.211)", text: $baseURL)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .keyboardType(.URL)
                
                TextField("API Key", text: $apiKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                
                TextField("PIN (SaaS only - optional)", text: $pin)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
            }
            
            HStack(spacing: 12) {
                Button("Test Connection") {
                    testConnection()
                }
                .buttonStyle(.borderedProminent)
                .disabled(baseURL.isEmpty || apiKey.isEmpty || isTestingConnection)
                
                Button("Advanced Settings") {
                    showingFullSettings = true
                }
                .buttonStyle(.bordered)
            }
            
            if isTestingConnection {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Testing connection...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Text("Enter your Netreo server IP address and API key to get started.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .cornerRadius(12)
        .sheet(isPresented: $showingFullSettings) {
            SettingsView()
        }
        .alert("Connection Test", isPresented: $showingAlert) {
            Button("OK") {
                connectionResult = nil
            }
        } message: {
            Text(connectionResult ?? "")
        }
    }
    
    private func testConnection() {
        isTestingConnection = true
        connectionResult = nil
        
        Task {
            do {
                // Format the URL properly
                let formattedURL = formatURL(baseURL)
                
                let apiVersion = NetreoAPIConfiguration.APIVersion(rawValue: apiVersionString) ?? .legacy
                let configuration = NetreoAPIConfiguration(
                    baseURL: formattedURL,
                    apiKey: apiKey,
                    pin: pin.isEmpty ? nil : pin,
                    version: apiVersion
                )
                
                let service = NetreoAPIService(configuration: configuration)
                let devices = try await service.fetchDevices()
                
                await MainActor.run {
                    isTestingConnection = false
                    connectionResult = "✅ Connection successful!\nFound \(devices.count) devices."
                    showingAlert = true
                }
            } catch {
                await MainActor.run {
                    isTestingConnection = false
                    connectionResult = "❌ Connection failed:\n\(error.localizedDescription)"
                    showingAlert = true
                }
            }
        }
    }
    
    private func formatURL(_ url: String) -> String {
        var formatted = url.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove trailing slash
        formatted = formatted.trimmingSuffix("/")
        
        // Add protocol if missing
        if !formatted.hasPrefix("http://") && !formatted.hasPrefix("https://") {
            formatted = "http://\(formatted)"
        }
        
        return formatted
    }
}

#Preview {
    QuickConfigView()
}