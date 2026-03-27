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
    var body: some View {
        ZStack {
            NavigationStack {
                Form {
                    // MARK: BHNM Servers list
                    Section(header: Text("BHNM Servers")) {
                        // Migration banner: shown when active connection has no bhnmURL set
                        if let active = savedConnections.first(where: { $0.id.uuidString == activeSavedConnectionID }),
                           active.bhnmURL.isEmpty {
                            Button {
                                editingConnection = active
                                showEditNavigation = true
                            } label: {
                                Label("Tap to complete setup — BHNM URL required", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.subheadline)
                            }
                        }
                        ForEach(savedConnections) { connection in
                            serverRow(connection)
                        }
                        Button {
                            navigateToAdd = true
                        } label: {
                            Label("Add BHNM Server", systemImage: "plus.circle.fill")
                                .foregroundColor(.accentColor)
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
                .onAppear { reload() }
                .onReceive(NotificationCenter.default.publisher(for: .deepLinkConnectionApplied)) { _ in
                    reload()
                }
            }

            // MARK: Centered switch-server popup
            if let conn = switchingToConnection {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { switchingToConnection = nil } }

                SwitchServerPopup(connection: conn) {
                    activateConnection(conn)
                    withAnimation(.easeInOut(duration: 0.2)) { switchingToConnection = nil }
                } onCancel: {
                    withAnimation(.easeInOut(duration: 0.2)) { switchingToConnection = nil }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: switchingToConnection?.id)
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
            HStack(spacing: 0) {
                rowContent
                    .contentShape(Rectangle())
                    .onTapGesture { switchingToConnection = connection }

                Button {
                    editingConnection = connection
                    showEditNavigation = true
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(.systemGray3))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
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
        }
    }

    private func serverRowContent(_ connection: SavedConnection, isActive: Bool, isSwitching: Bool) -> some View {
        let displayHost = connection.bhnmURL.isEmpty ? connection.middlewareURL : connection.bhnmURL
        return HStack(spacing: 10) {
            // Active indicator — space reserved for all rows so icons stay aligned
            ZStack {
                if isActive {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color(red: 0.55, green: 1.0, blue: 0.55),
                                         Color(red: 0.0,  green: 0.65, blue: 0.15)],
                                center: UnitPoint(x: 0.35, y: 0.3),
                                startRadius: 0,
                                endRadius: 8
                            )
                        )
                        .frame(width: 14, height: 14)
                        .shadow(color: .green.opacity(0.55), radius: 4, x: 0, y: 2)
                        .shadow(color: .black.opacity(0.25), radius: 1, x: 0, y: 1)
                }
            }
            .frame(width: 14)

            ServerIconView(symbol: connection.symbol, accentColor: connection.accentColor, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(connection.name).font(.body)
                Text(hostname(displayHost))
                    .font(.caption).foregroundColor(isActive ? .green : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isSwitching { ProgressView() }
        }
    }

    // MARK: - Actions

    private func reload() {
        savedConnections = UserDefaults.standard.loadSavedConnections()
    }

    private func activateConnection(_ new: SavedConnection) {
        switchingInProgress = new.id

        // Sync all credentials for the new connection
        UserDefaults.standard.set(new.middlewareURL,  forKey: "netreo_base_url")
        UserDefaults.standard.set(new.bhnmURL,        forKey: "netreo_bhnm_url")
        UserDefaults.standard.set(new.apiKey,         forKey: "netreo_api_key")
        UserDefaults.standard.set(new.pin,            forKey: "netreo_pin")
        UserDefaults.standard.set(new.ackUser,        forKey: "netreo_ack_user")
        UserDefaults.standard.set(new.webhookSecret,  forKey: "netreo_webhook_secret")
        activeSavedConnectionID = new.id.uuidString
        // Push registration for the new connection fires via ContentView.onChange(of: activeConnectionID)

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

// MARK: - SwitchServerPopup

private struct SwitchServerPopup: View {
    let connection: SavedConnection
    let onSwitch: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                ServerIconView(symbol: connection.symbol, accentColor: connection.accentColor, size: 60)
                VStack(spacing: 4) {
                    Text(connection.name)
                        .font(.title3).fontWeight(.semibold)
                    Text(hostname(connection.bhnmURL.isEmpty ? connection.middlewareURL : connection.bhnmURL))
                        .font(.subheadline).foregroundColor(.secondary)
                }
                Text("Switch to this server?")
                    .font(.footnote).foregroundColor(.secondary)
            }
            .padding(.top, 28)
            .padding(.bottom, 24)
            .padding(.horizontal, 24)

            Divider()

            // Buttons
            HStack(spacing: 0) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.body)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .foregroundColor(.secondary)

                Divider().frame(height: 52)

                Button(action: onSwitch) {
                    Text("Switch")
                        .font(.body).fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .foregroundColor(.accentColor)
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(18)
        .shadow(color: .black.opacity(0.25), radius: 30, x: 0, y: 10)
        .padding(.horizontal, 40)
    }

    private func hostname(_ urlString: String) -> String {
        URL(string: urlString)?.host ?? urlString
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
