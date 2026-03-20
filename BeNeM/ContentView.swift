import SwiftUI

struct ContentView: View {
    @AppStorage("netreo_base_url") private var baseURL = ""
    @AppStorage("netreo_api_key") private var apiKey = ""
    @AppStorage("netreo_pin") private var pin = ""
    @AppStorage("netreo_api_version") private var apiVersionString = "legacy"
    @AppStorage("netreo_timeout") private var timeout: Double = 30.0
    @AppStorage("netreo_retry_count") private var retryCount: Double = 3.0

    @State private var apiService: NetreoAPIService?
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            if !baseURL.isEmpty && !apiKey.isEmpty, let service = apiService {
                DashboardView(apiService: service, selectedTab: $selectedTab)
                    .tag(0)
                IncidentListView(apiService: service)
                    .tag(1)
                DeviceListView(apiService: service)
                    .tag(2)
            } else {
                WelcomeView()
                    .tag(0)
            }
            SettingsView()
                .tag(3)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CustomTabBar(selectedTab: $selectedTab, isConfigured: apiService != nil)
        }
        .onChange(of: baseURL) { _, _ in updateAPIService() }
        .onChange(of: apiKey) { _, _ in updateAPIService() }
        .onChange(of: pin) { _, _ in updateAPIService() }
        .onChange(of: apiVersionString) { _, _ in updateAPIService() }
        .onChange(of: timeout) { _, _ in updateAPIService() }
        .onChange(of: retryCount) { _, _ in updateAPIService() }
        .onChange(of: apiService == nil) { _, isNil in
            if isNil { selectedTab = 0 }
        }
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

// MARK: - Custom Tab Bar

private struct CustomTabBar: View {
    @Binding var selectedTab: Int
    let isConfigured: Bool

    var body: some View {
        HStack(spacing: 0) {
            if isConfigured {
                tabButton(tag: 0, icon: "house.fill",                    label: "Dashboard", color: .green)
                tabButton(tag: 1, icon: "exclamationmark.triangle.fill", label: "Incidents", color: .red)
                tabButton(tag: 2, icon: "network",                       label: "Devices",   color: .blue)
                tabButton(tag: 3, icon: "gear",                          label: "Settings",  color: Color(.systemGray))
            } else {
                tabButton(tag: 0, icon: "house", label: "Home",     color: Color(.systemGray))
                tabButton(tag: 3, icon: "gear",  label: "Settings", color: Color(.systemGray))
            }
        }
        .frame(height: 49)
        .background {
            Rectangle()
                .fill(.bar)
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) { Divider() }
        }
    }

    private func tabButton(tag: Int, icon: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { selectedTab = tag }
    }
}

// MARK: - WelcomeView

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
