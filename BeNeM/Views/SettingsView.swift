import SwiftUI

struct SettingsView: View {
    @AppStorage("netreo_api_version")   private var apiVersionString = "legacy"
    @AppStorage("netreo_timeout")       private var timeout: Double = 30.0
    @AppStorage("netreo_retry_count")   private var retryCount: Double = 3.0
    @AppStorage("refresh_interval")     private var refreshInterval: Double = 120.0
    @AppStorage("maxDevicesCount")      private var maxDevicesCount: Int = 20
    @AppStorage("netreo_active_connection_id") private var activeSavedConnectionID = ""

    @State private var savedConnections: [SavedConnection] = []
    @State private var switchingToConnection: SavedConnection? = nil
    @State private var switchingInProgress: UUID? = nil
    @State private var editingConnection: SavedConnection? = nil   // drives swipe-to-edit navigation
    @State private var showEditNavigation = false                   // paired with editingConnection
    @State private var navigateToAdd = false                        // drives + toolbar navigation
    @State private var isClassCWiFiAvailable = NetworkDiscovery.isOnClassCWiFi

    var body: some View {
        NavigationView {
            Form {
                // MARK: Discovery
                Section(
                    header: Text("Discovery"),
                    footer: Text(isClassCWiFiAvailable
                        ? "Scans your Wi‑Fi network for BHNM servers."
                        : "Requires a Wi‑Fi connection with a /24 (Class C) subnet.")
                ) {
                    NavigationLink(destination: AutoDiscoveryView()) {
                        Label("Discover BHNM Server", systemImage: "magnifyingglass.circle.fill")
                    }
                    .disabled(!isClassCWiFiAvailable)
                }

                // MARK: BHNM Servers list
                Section(header: Text("BHNM Servers")) {
                    if savedConnections.isEmpty {
                        Button {
                            navigateToAdd = true
                        } label: {
                            Label("Add BHNM Server", systemImage: "plus.circle.fill")
                                .foregroundColor(.accentColor)
                        }
                    } else {
                        ForEach(savedConnections) { connection in
                            serverRow(connection)
                        }
                    }
                }

                // MARK: Refresh
                Section(header: Text("Refresh")) {
                    VStack(alignment: .leading) {
                        Text("Auto-Refresh: \(Int(refreshInterval))s")
                        Slider(value: $refreshInterval, in: 30...300, step: 10)
                    }
                }

                // MARK: Devices
                Section(header: Text("Devices")) {
                    Stepper("Load up to \(maxDevicesCount) devices",
                            value: $maxDevicesCount, in: 10...100, step: 10)
                    Text("Limits how many devices are loaded in the Devices tab.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // MARK: API Configuration
                Section(header: Text("API Configuration")) {
                    Picker("API Version", selection: Binding(
                        get: { NetreoAPIConfiguration.APIVersion(rawValue: apiVersionString) ?? .legacy },
                        set: { apiVersionString = $0.rawValue }
                    )) {
                        ForEach(NetreoAPIConfiguration.APIVersion.allCases, id: \.self) { v in
                            Text(v.displayName).tag(v)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())

                    VStack(alignment: .leading) {
                        Text("Timeout: \(Int(timeout))s")
                        Slider(value: $timeout, in: 10...120, step: 5)
                    }
                    VStack(alignment: .leading) {
                        Text("Retry Count: \(Int(retryCount))")
                        Slider(value: $retryCount, in: 1...10, step: 1)
                    }
                }

                // MARK: About
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersionString).foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            // NavigationLink inside swipeActions is not supported in SwiftUI.
            // Use @State + navigationDestination instead for both swipe-edit and + button navigation.
            .navigationDestination(isPresented: $showEditNavigation) {
                if let conn = editingConnection {
                    ServerConfigView(existingConnection: conn)
                }
            }
            .navigationDestination(isPresented: $navigateToAdd) {
                ServerConfigView(existingConnection: nil)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { navigateToAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .onAppear {
                isClassCWiFiAvailable = NetworkDiscovery.isOnClassCWiFi
                reload()
            }
            .onReceive(NotificationCenter.default.publisher(for: .deepLinkConnectionApplied)) { _ in
                reload()
            }
            .confirmationDialog(
                "Switch to \"\(switchingToConnection?.name ?? "")\"?",
                isPresented: Binding(get: { switchingToConnection != nil }, set: { if !$0 { switchingToConnection = nil } }),
                titleVisibility: .visible
            ) {
                Button("Switch") {
                    if let conn = switchingToConnection { activateConnection(conn) }
                    switchingToConnection = nil
                }
                Button("Cancel", role: .cancel) { switchingToConnection = nil }
            }
        }
    }

    // MARK: - Server row
    // Active row → NavigationLink to edit. Inactive row → onTapGesture → confirmation dialog.
    // Swipe left on any row shows Edit action.

    @ViewBuilder
    private func serverRow(_ connection: SavedConnection) -> some View {
        let isActive = connection.id.uuidString == activeSavedConnectionID
        let isSwitching = switchingInProgress == connection.id
        let rowContent = serverRowContent(connection, isActive: isActive, isSwitching: isSwitching)

        // Swipe-to-edit uses @State editingConnection + .navigationDestination (NavigationLink
        // is not supported inside swipeActions). Active row taps navigate via NavigationLink.
        if isActive {
            NavigationLink(destination: ServerConfigView(existingConnection: connection)) {
                rowContent
            }
            .swipeActions(edge: .trailing) {
                Button {
                    editingConnection = connection
                    showEditNavigation = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(.blue)
            }
        } else {
            rowContent
                .contentShape(Rectangle())
                .onTapGesture { switchingToConnection = connection }
                .swipeActions(edge: .trailing) {
                    Button {
                        editingConnection = connection
                        showEditNavigation = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
        }
    }

    private func serverRowContent(_ connection: SavedConnection, isActive: Bool, isSwitching: Bool) -> some View {
        HStack(spacing: 12) {
            ServerIconView(symbol: connection.symbol, accentColor: connection.accentColor, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name).font(.body)
                if isActive {
                    Text("Active · \(hostname(connection.baseURL))")
                        .font(.caption).foregroundColor(.green)
                } else {
                    Text(hostname(connection.baseURL))
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if isSwitching { ProgressView() }
        }
    }

    // MARK: - Actions

    private func reload() {
        savedConnections = UserDefaults.standard.loadSavedConnections()
    }

    private func activateConnection(_ connection: SavedConnection) {
        switchingInProgress = connection.id
        UserDefaults.standard.set(connection.baseURL, forKey: "netreo_base_url")
        UserDefaults.standard.set(connection.apiKey,  forKey: "netreo_api_key")
        UserDefaults.standard.set(connection.pin,     forKey: "netreo_pin")
        UserDefaults.standard.set(connection.ackUser, forKey: "netreo_ack_user")
        activeSavedConnectionID = connection.id.uuidString
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            switchingInProgress = nil
            reload()
        }
    }

    // MARK: - Helpers

    private func hostname(_ urlString: String) -> String {
        URL(string: urlString)?.host ?? urlString
    }

    private var appVersionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }
}

extension NetreoAPIConfiguration.APIVersion {
    var displayName: String {
        switch self {
        case .legacy:
            return "Legacy (PHP APIs)"
        case .v1:
            return "API v1"
        case .v2:
            return "API v2"
        case .openapi:
            return "OpenAPI 3.0"
        }
    }

    var description: String {
        switch self {
        case .legacy:
            return "Original PHP-based APIs using form-encoded requests"
        case .v1:
            return "First generation REST API with JSON"
        case .v2:
            return "Second generation REST API with enhanced features"
        case .openapi:
            return "Modern OpenAPI 3.0 compliant endpoints"
        }
    }
}
