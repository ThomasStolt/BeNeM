import SwiftUI

struct SettingsView: View {
    @AppStorage("netreo_base_url") private var baseURL = ""
    @AppStorage("netreo_api_key") private var apiKey = ""
    @AppStorage("netreo_pin") private var pin = ""
    @AppStorage("netreo_ack_user") private var ackUser = ""
    @AppStorage("netreo_api_version") private var apiVersionString = "legacy"
    @AppStorage("netreo_timeout") private var timeout: Double = 30.0
    @AppStorage("netreo_retry_count") private var retryCount: Double = 3.0
    @AppStorage("refresh_interval") private var refreshInterval: Double = 120.0
    @AppStorage("maxDevicesCount") private var maxDevicesCount: Int = 20

    // Draft state — held locally until Save is tapped
    @State private var draftBaseURL = ""
    @State private var draftApiKey = ""
    @State private var draftPin = ""
    @State private var draftAckUser = ""
    @State private var draftName = "New Server"
    @AppStorage("netreo_active_connection_id") private var activeSavedConnectionID: String = ""
    private var activeSavedUUID: UUID? { UUID(uuidString: activeSavedConnectionID) }
    @State private var savedConnections: [SavedConnection] = []

    private enum Field: Hashable { case name, baseURL, apiKey, pin, ackUser }
    @FocusState private var focusedField: Field?

    private enum TestStatus { case untested, success, failure }
    @State private var testStatus: TestStatus = .untested
    @State private var isTesting = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showingAlert = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Discovery")) {
                    NavigationLink(destination: AutoDiscoveryView()) {
                        Label("Auto Discovery", systemImage: "magnifyingglass.circle.fill")
                    }
                }

                Section(header: Text("BHNM Server")) {
                    HStack {
                        if testStatus != .untested {
                            Circle()
                                .fill(testStatus == .success ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                        }
                        TextField("Connection Name", text: $draftName)
                            .autocapitalization(.none)
                            .focused($focusedField, equals: .name)
                        Menu {
                            ForEach(savedConnections) { connection in
                                Button {
                                    selectConnection(connection)
                                } label: {
                                    if connection.id.uuidString == activeSavedConnectionID {
                                        Label(connection.name, systemImage: "checkmark")
                                    } else {
                                        Text(connection.name)
                                    }
                                }
                            }
                            if !savedConnections.isEmpty { Divider() }
                            Button("New Server") {
                                selectNewConnection()
                            }
                        } label: {
                            Image(systemName: "chevron.up.chevron.down")
                                .foregroundColor(.secondary)
                        }
                    }

                    TextField("Base URL", text: $draftBaseURL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                        .focused($focusedField, equals: .baseURL)

                    SecureField("API Key", text: $draftApiKey)
                        .focused($focusedField, equals: .apiKey)

                    SecureField("PIN (SaaS only)", text: $draftPin)
                        .focused($focusedField, equals: .pin)

                    TextField("ACK User", text: $draftAckUser)
                        .autocapitalization(.none)
                        .focused($focusedField, equals: .ackUser)

                    HStack(spacing: 0) {
                        Button {
                            Task { await testConnection() }
                        } label: {
                            Group {
                                if isTesting {
                                    ProgressView()
                                } else {
                                    Text("Test")
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderless)
                        .disabled(draftBaseURL.isEmpty || draftApiKey.isEmpty || draftName.isEmpty || isTesting)

                        Divider().frame(height: 44)

                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderless)
                        .disabled(activeSavedUUID == nil)
                    }
                }

                Section(header: Text("Refresh")) {
                    VStack(alignment: .leading) {
                        Text("Auto-Refresh: \(Int(refreshInterval))s")
                        Slider(value: $refreshInterval, in: 30...300, step: 10)
                    }
                }

                Section(header: Text("Devices")) {
                    Stepper("Load up to \(maxDevicesCount) devices",
                            value: $maxDevicesCount, in: 10...100, step: 10)
                    Text("Limits how many devices are loaded in the Devices tab. Increase if you have a large estate.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("API Configuration")) {
                    Picker("API Version", selection: Binding(
                        get: { NetreoAPIConfiguration.APIVersion(rawValue: apiVersionString) ?? .legacy },
                        set: { apiVersionString = $0.rawValue }
                    )) {
                        ForEach(NetreoAPIConfiguration.APIVersion.allCases, id: \.self) { version in
                            Text(version.displayName).tag(version)
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

                Section(footer: Text("Enter your BHNM server details to connect to BMC Helix Network Management. Choose the appropriate API version based on your deployment.")) {
                    EmptyView()
                }

            }
            .navigationTitle("Settings")
            .scrollDismissesKeyboard(.immediately)
            .simultaneousGesture(TapGesture().onEnded { focusedField = nil })
            .alert(alertTitle, isPresented: $showingAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .alert("Delete '\(draftName)'?", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    deleteActiveConnection()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This connection will be removed from your saved list.")
            }
            .onAppear {
                savedConnections = UserDefaults.standard.loadSavedConnections()
                draftBaseURL = baseURL
                draftApiKey  = apiKey
                draftPin     = pin
                draftAckUser = ackUser
                // Restore display name from persisted active connection ID
                if let match = savedConnections.first(where: { $0.id.uuidString == activeSavedConnectionID }) {
                    draftName = match.name
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        focusedField = nil
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .deepLinkConnectionApplied)) { _ in
                savedConnections = UserDefaults.standard.loadSavedConnections()
                draftBaseURL = baseURL
                draftApiKey  = apiKey
                draftPin     = pin
                draftAckUser = ackUser
                if let match = savedConnections.first(where: { $0.id.uuidString == activeSavedConnectionID }) {
                    draftName = match.name
                }
            }
        }
    }

    @MainActor
    private func testConnection() async {
        focusedField = nil
        isTesting = true
        defer { isTesting = false }

        let trimmedURL = draftBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL), url.scheme != nil, url.host != nil else {
            alertTitle = "Invalid URL"
            alertMessage = "The URL \"\(trimmedURL)\" is not a valid format.\n\nExample: https://netreo.example.com"
            showingAlert = true
            return
        }

        // Always test against the actual endpoint the app uses at runtime
        guard let testURL = URL(string: "\(trimmedURL.trimmingSuffix("/"))/fw/index.php?r=restful/devices/list") else {
            alertTitle = "Invalid URL"
            alertMessage = "Could not construct test URL from \"\(trimmedURL)\"."
            showingAlert = true
            return
        }

        var request = URLRequest(url: testURL, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyItems = [URLQueryItem(name: "password", value: draftApiKey)]
        if !draftPin.isEmpty {
            bodyItems.append(URLQueryItem(name: "pin", value: draftPin))
        }
        var comps = URLComponents()
        comps.queryItems = bodyItems
        request.httpBody = comps.percentEncodedQuery?.data(using: .utf8)

        do {
            let sessionConfig = URLSessionConfiguration.default
            sessionConfig.timeoutIntervalForRequest = 15
            let session = URLSession(configuration: sessionConfig)

            let (data, response) = try await session.data(for: request)
            let http = response as! HTTPURLResponse
            let statusCode = http.statusCode

            switch statusCode {
            case 200:
                // Parse device count using the same two-shape JSON the app handles at runtime
                var deviceCount = 0
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let arr = json["devices"] as? [[String: Any]] {
                        deviceCount = arr.count
                    } else if let nested = json["data"] as? [String: Any],
                              let arr = nested["devices"] as? [[String: Any]] {
                        deviceCount = arr.count
                    }
                }
                if deviceCount > 0 {
                    // Upsert into savedConnections
                    let trimmedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let now = SavedConnection(
                        id: activeSavedUUID ?? UUID(),
                        name: trimmedName.isEmpty ? "Unnamed" : trimmedName,
                        baseURL: draftBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                        apiKey: draftApiKey,
                        pin: draftPin,
                        ackUser: draftAckUser
                    )
                    if let idx = savedConnections.firstIndex(where: { $0.id == now.id }) {
                        savedConnections[idx] = now
                    } else {
                        savedConnections.append(now)
                    }
                    UserDefaults.standard.saveSavedConnections(savedConnections)
                    activeSavedConnectionID = now.id.uuidString

                    // Write to @AppStorage (triggers ContentView.updateAPIService via onChange)
                    baseURL  = now.baseURL
                    apiKey   = now.apiKey
                    pin      = now.pin
                    ackUser  = now.ackUser

                    testStatus = .success
                    return  // success — no alert
                } else {
                    testStatus = .failure
                    alertTitle   = "Connected — no devices found"
                    alertMessage = "The server responded successfully but returned no devices.\n\nCheck that your API key has permission to list devices."
                }
            case 401, 403:
                testStatus = .failure
                alertTitle = "Authentication failed"
                alertMessage = "HTTP \(statusCode): The server rejected the credentials.\n\nCheck your API key and PIN."
            case 404:
                testStatus = .failure
                alertTitle = "Endpoint not found"
                alertMessage = "HTTP 404: The API endpoint was not found.\n\nCheck the base URL."
            case 500...599:
                testStatus = .failure
                alertTitle = "Server error"
                alertMessage = "HTTP \(statusCode): The server reported an internal error."
            default:
                testStatus = .failure
                let bodyPreview = String(data: data.prefix(300), encoding: .utf8) ?? "(unreadable)"
                alertTitle = "Unexpected response"
                alertMessage = "HTTP \(statusCode)\n\nResponse: \(bodyPreview)"
            }
        } catch let urlError as URLError {
            testStatus = .failure
            alertTitle = "Connection failed"
            switch urlError.code {
            case .notConnectedToInternet:
                alertMessage = "No internet connection."
            case .cannotFindHost:
                alertMessage = "Host not found: \"\(url.host ?? trimmedURL)\" could not be resolved.\n\nCheck the URL and that your VPN is connected if this is an internal server."
            case .cannotConnectToHost:
                alertMessage = "Cannot connect to \"\(url.host ?? trimmedURL)\".\n\nCheck the URL, port, and firewall settings."
            case .timedOut:
                alertMessage = "Timed out after 15 seconds.\n\nURL: \(testURL.absoluteString)"
            case .secureConnectionFailed, .serverCertificateUntrusted:
                alertMessage = "SSL/TLS error: \(urlError.localizedDescription)"
            default:
                alertMessage = "\(urlError.localizedDescription) (code \(urlError.code.rawValue))"
            }
        } catch {
            testStatus = .failure
            alertTitle = "Error"
            alertMessage = error.localizedDescription
        }

        showingAlert = true
    }

    private func selectConnection(_ connection: SavedConnection) {
        testStatus   = .untested
        draftName    = connection.name
        draftBaseURL = connection.baseURL
        draftApiKey  = connection.apiKey
        draftPin     = connection.pin
        draftAckUser = connection.ackUser
        activeSavedConnectionID = connection.id.uuidString
        Task { await testConnection() }
    }

    private func selectNewConnection() {
        testStatus   = .untested
        draftName    = "New Server"
        draftBaseURL = ""
        draftApiKey  = ""
        draftPin     = ""
        draftAckUser = ""
        activeSavedConnectionID = ""
    }

    private func deleteActiveConnection() {
        guard let id = activeSavedUUID else { return }
        savedConnections.removeAll { $0.id == id }
        UserDefaults.standard.saveSavedConnections(savedConnections)
        activeSavedConnectionID = ""
        testStatus   = .untested
        // Clear all draft fields — user must pick or configure a new connection.
        draftName    = "New Server"
        draftBaseURL = ""
        draftApiKey  = ""
        draftPin     = ""
        draftAckUser = ""
        // Clear @AppStorage — disconnects the current service.
        // If no connections remain, ContentView sets apiService = nil → WelcomeView.
        baseURL  = ""
        apiKey   = ""
        pin      = ""
        ackUser  = ""
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