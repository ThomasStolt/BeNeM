import SwiftUI

struct ContentView: View {
    @AppStorage("netreo_base_url") private var baseURL = ""
    @AppStorage("netreo_api_key") private var apiKey = ""
    @AppStorage("netreo_pin") private var pin = ""
    @AppStorage("netreo_api_version") private var apiVersionString = "legacy"
    @AppStorage("netreo_timeout") private var timeout: Double = 30.0
    @AppStorage("netreo_retry_count") private var retryCount: Double = 3.0
    @AppStorage("netreo_active_connection_id") private var activeConnectionID = ""
    @AppStorage("netreo_webhook_secret") private var webhookSecret = ""
    @AppStorage("netreo_bhnm_url") private var bhnmURL = ""

    @StateObject private var incidentViewModel = IncidentListViewModel(
        apiService: NetreoAPIService(baseURL: "https://placeholder.invalid", apiKey: "placeholder")
    )

    @State private var apiService: NetreoAPIService?
    @State private var selectedTab = 0
    @State private var homeNavResetID = UUID()
    @State private var incidentNavResetID = UUID()
    @State private var settingsNavResetID = UUID()
    @State private var pendingIncidentID: String? = nil
    @State private var keyboardVisible = false

    var body: some View {
        tabContentWithHandlers
            .onReceive(NotificationCenter.default.publisher(for: .pushNotificationIncidentTapped)) { notification in
                guard let id = notification.userInfo?["incident_id"] as? String else {
                    print("[DeepLink] No incident_id in notification")
                    return
                }
                print("[DeepLink] Notification tapped — incident_id: \(id)")
                // Reset nav path first if already on Incidents tab, then set pending ID
                // after a brief delay to avoid the navReset clearing our navigation.
                if selectedTab == 1 {
                    incidentNavResetID = UUID()
                }
                selectedTab = 1
                // Delay setting pendingIncidentID to let navPath reset settle
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    pendingIncidentID = id
                }
            }
            .onAppear {
                updateAPIService()
                if apiService == nil { selectedTab = 3 }
                consumePendingDeepLink()
                // Retry after a short delay — didReceive may fire after onAppear on cold launch
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    consumePendingDeepLink()
                }
            }
    }

    private var tabContentWithHandlers: some View {
        tabContent
            .onChange(of: selectedTab) { _, newTab in
                if newTab == 3 { settingsNavResetID = UUID() }
            }
            .onChange(of: baseURL) { _, _ in updateAPIService() }
            .onChange(of: bhnmURL) { _, _ in updateAPIService() }
            .onChange(of: apiKey) { _, _ in updateAPIService() }
            .onChange(of: pin) { _, _ in updateAPIService() }
            .onChange(of: apiVersionString) { _, _ in updateAPIService() }
            .onChange(of: timeout) { _, _ in updateAPIService() }
            .onChange(of: retryCount) { _, _ in updateAPIService() }
            .onChange(of: webhookSecret) { _, _ in updateAPIService() }
            .onChange(of: activeConnectionID) { oldID, newID in
                handleConnectionChange(from: oldID, to: newID)
            }
            .onChange(of: apiService == nil) { _, isNil in
                if isNil { selectedTab = 3 }
            }
    }

    @ViewBuilder
    private var mainTabs: some View {
        if !baseURL.isEmpty && !apiKey.isEmpty, let service = apiService {
            DashboardView(apiService: service, incidentViewModel: incidentViewModel, selectedTab: $selectedTab, navResetID: homeNavResetID)
                .tag(0)
            IncidentListView(viewModel: incidentViewModel, apiService: service, navResetID: incidentNavResetID, pendingIncidentID: $pendingIncidentID)
                .tag(1)
            DeviceListView(apiService: service, incidentViewModel: incidentViewModel)
                .tag(2)
        }
        SettingsView(navResetID: settingsNavResetID)
            .tag(3)
    }

    private var tabBar: some View {
        CustomTabBar(selectedTab: $selectedTab, isConfigured: apiService != nil) { tappedTag in
            if tappedTag == 0 { homeNavResetID = UUID() }
            if tappedTag == 1 { incidentNavResetID = UUID() }
            if tappedTag == 3 { settingsNavResetID = UUID() }
        }
    }

    private var tabContent: some View {
        TabView(selection: $selectedTab) {
            mainTabs
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !keyboardVisible {
                tabBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: keyboardVisible)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
    }

    private func handleConnectionChange(from oldID: String, to newID: String) {
        let connections = UserDefaults.standard.loadSavedConnections()
        if !oldID.isEmpty,
           let oldConn = connections.first(where: { $0.id.uuidString == oldID }),
           oldConn.notificationsEnabled,
           !oldConn.middlewareURL.isEmpty,
           let token = AppDelegate.shared?.cachedDeviceToken {
            AppDelegate.shared?.unregisterWithMiddleware(
                token: token,
                secret: oldConn.webhookSecret,
                middlewareURL: oldConn.middlewareURL
            )
        }
        // Always update the server name subtitle
        UserDefaults.standard.removeObject(forKey: "netreo_active_connection_name")
        guard !newID.isEmpty,
              let conn = connections.first(where: { $0.id.uuidString == newID }) else { return }
        UserDefaults.standard.set(conn.name, forKey: "netreo_active_connection_name")
        // Push registration is conditional on notifications being enabled and token available
        guard conn.notificationsEnabled,
              let token = AppDelegate.shared?.cachedDeviceToken else { return }
        UserDefaults.standard.set(conn.webhookSecret, forKey: "netreo_webhook_secret")
        AppDelegate.shared?.registerWithMiddleware(
            token: token,
            secret: conn.webhookSecret,
            middlewareURL: conn.middlewareURL
        )
    }

    private func consumePendingDeepLink() {
        if let id = AppDelegate.shared?.pendingIncidentID {
            print("[DeepLink] consumePendingDeepLink — incident_id: \(id)")
            AppDelegate.shared?.pendingIncidentID = nil
            selectedTab = 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
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
            bhnmURL: bhnmURL,
            apiKey: apiKey,
            pin: pin.isEmpty ? nil : pin,
            proxyToken: webhookSecret,
            version: apiVersion,
            timeout: timeout,
            retryCount: Int(retryCount)
        )
        let service = NetreoAPIService(configuration: configuration)
        apiService = service
        incidentViewModel.updateAPIService(service)
        // Reset all navigation stacks so stale data from the old server is never shown
        homeNavResetID = UUID()
        incidentNavResetID = UUID()
        settingsNavResetID = UUID()
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
