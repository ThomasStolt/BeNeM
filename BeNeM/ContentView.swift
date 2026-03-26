import SwiftUI

struct ContentView: View {
    @AppStorage("netreo_base_url") private var baseURL = ""
    @AppStorage("netreo_api_key") private var apiKey = ""
    @AppStorage("netreo_pin") private var pin = ""
    @AppStorage("netreo_api_version") private var apiVersionString = "legacy"
    @AppStorage("netreo_timeout") private var timeout: Double = 30.0
    @AppStorage("netreo_retry_count") private var retryCount: Double = 3.0
    @AppStorage("netreo_active_connection_id") private var activeConnectionID = ""

    @State private var apiService: NetreoAPIService?
    @State private var selectedTab = 0
    @State private var homeNavResetID = UUID()
    @State private var incidentNavResetID = UUID()
    @State private var pendingIncidentID: String? = nil

    var body: some View {
        TabView(selection: $selectedTab) {
            if !baseURL.isEmpty && !apiKey.isEmpty, let service = apiService {
                DashboardView(apiService: service, selectedTab: $selectedTab, navResetID: homeNavResetID)
                    .tag(0)
                IncidentListView(apiService: service, navResetID: incidentNavResetID, pendingIncidentID: $pendingIncidentID)
                    .tag(1)
                DeviceListView(apiService: service)
                    .tag(2)
            }
            SettingsView()
                .tag(3)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CustomTabBar(selectedTab: $selectedTab, isConfigured: apiService != nil) { tappedTag in
                if tappedTag == 0 { homeNavResetID = UUID() }
                if tappedTag == 1 { incidentNavResetID = UUID() }
            }
        }
        .onChange(of: baseURL) { _, _ in updateAPIService() }
        .onChange(of: apiKey) { _, _ in updateAPIService() }
        .onChange(of: pin) { _, _ in updateAPIService() }
        .onChange(of: apiVersionString) { _, _ in updateAPIService() }
        .onChange(of: timeout) { _, _ in updateAPIService() }
        .onChange(of: retryCount) { _, _ in updateAPIService() }
        .onChange(of: activeConnectionID) { _, newID in
            guard !newID.isEmpty,
                  let token = AppDelegate.shared?.cachedDeviceToken else { return }
            let connections = UserDefaults.standard.loadSavedConnections()
            if let conn = connections.first(where: { $0.id.uuidString == newID }) {
                AppDelegate.shared?.registerWithMiddleware(
                    token: token,
                    secret: conn.webhookSecret,
                    middlewareURL: conn.pushMiddlewareURL
                )
            }
        }
        .onChange(of: apiService == nil) { _, isNil in
            if isNil { selectedTab = 3 }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pushNotificationIncidentTapped)) { notification in
            guard let id = notification.userInfo?["incident_id"] as? String else { return }
            if selectedTab == 1 { incidentNavResetID = UUID() }
            selectedTab = 1
            pendingIncidentID = id
        }
        .onAppear {
            updateAPIService()
            if apiService == nil { selectedTab = 3 }
            if let id = AppDelegate.shared?.pendingIncidentID {
                AppDelegate.shared?.pendingIncidentID = nil
                selectedTab = 1
                pendingIncidentID = id
            }
        }
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
    let onSameTabTap: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            if isConfigured {
                tabButton(tag: 0, icon: "house.fill",                    label: "Home",      color: .green)
                tabButton(tag: 1, icon: "exclamationmark.triangle.fill", label: "Incidents", color: .red)
                tabButton(tag: 2, icon: "network",                       label: "Devices",   color: .blue)
                tabButton(tag: 3, icon: "gear",                          label: "Settings",  color: Color(.systemGray))
            } else {
                tabButton(tag: 3, icon: "gear", label: "Settings", color: Color(.systemGray))
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
        let isSelected = selectedTab == tag
        return VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(color)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color(.systemGray3) : Color.clear, lineWidth: 1.5)
        )
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            if selectedTab == tag {
                onSameTabTap(tag)
            } else {
                selectedTab = tag
            }
        }
    }
}


#Preview {
    ContentView()
}
