import SwiftUI

struct ContentView: View {
    @AppStorage("netreo_base_url") private var baseURL = ""
    @AppStorage("netreo_api_key") private var apiKey = ""
    @AppStorage("netreo_pin") private var pin = ""
    @AppStorage("netreo_api_version") private var apiVersionString = "legacy"
    @AppStorage("netreo_timeout") private var timeout: Double = 30.0
    @AppStorage("netreo_retry_count") private var retryCount: Double = 3.0
    
    @State private var apiService: NetreoAPIService?
    
    var body: some View {
        TabView {
            if !baseURL.isEmpty && !apiKey.isEmpty, let service = apiService {
                DashboardView(apiService: service)
                    .tabItem {
                        Image(systemName: "house.fill")
                        Text("Dashboard")
                    }
                
                IncidentListView(apiService: service)
                    .tabItem {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Incidents")
                    }
                
                DeviceListView(apiService: service)
                    .tabItem {
                        Image(systemName: "network")
                        Text("Devices")
                    }
            } else {
                WelcomeView()
                    .tabItem {
                        Image(systemName: "house")
                        Text("Home")
                    }
            }
            
            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text("Settings")
                }
        }
        .onChange(of: baseURL) { _, _ in updateAPIService() }
        .onChange(of: apiKey) { _, _ in updateAPIService() }
        .onChange(of: pin) { _, _ in updateAPIService() }
        .onChange(of: apiVersionString) { _, _ in updateAPIService() }
        .onChange(of: timeout) { _, _ in updateAPIService() }
        .onChange(of: retryCount) { _, _ in updateAPIService() }
        .onAppear { updateAPIService() }
    }
    
    private func updateAPIService() {
        guard !baseURL.isEmpty && !apiKey.isEmpty else {
            apiService = nil
            return
        }
        
        let apiVersion = NetreoAPIConfiguration.APIVersion(rawValue: apiVersionString) ?? .legacy
        let configuration = NetreoAPIConfiguration(
            baseURL: baseURL,
            apiKey: apiKey,
            pin: pin.isEmpty ? nil : pin,
            version: apiVersion,
            timeout: timeout,
            retryCount: Int(retryCount)
        )
        apiService = NetreoAPIService(configuration: configuration)
    }
}

struct WelcomeView: View {
    var body: some View {
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
                    
                    QuickConfigView()
                    
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
}

#Preview {
    ContentView()
}