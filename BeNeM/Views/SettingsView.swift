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
    @State private var activeSavedID: UUID? = nil
    @State private var savedConnections: [SavedConnection] = []

    private enum Field: Hashable { case name, baseURL, apiKey, pin, ackUser }
    @FocusState private var focusedField: Field?

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
                        TextField("Name", text: $draftName)
                            .autocapitalization(.none)
                            .focused($focusedField, equals: .name)
                        Menu {
                            ForEach(savedConnections) { connection in
                                Button(connection.name) {
                                    selectConnection(connection)
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
                            HStack(spacing: 6) {
                                if isTesting { ProgressView() }
                                Text(isTesting ? "Testing…" : "Test Connection")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderless)
                        .disabled(draftBaseURL.isEmpty || draftApiKey.isEmpty || draftName.isEmpty || isTesting)

                        Divider().frame(height: 44)

                        Button("Delete", role: .destructive) {
                            showingDeleteConfirmation = true
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.borderless)
                        .disabled(activeSavedID == nil)
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

                #if DEBUG
                Section(header: Text("Debug — CPU response (known working)")) {
                    Text(UserDefaults.standard.string(forKey: "debug_raw_cpu_response") ?? "(open any device detail to populate)")
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
                Section(header: Text("Debug — Interface response")) {
                    Text(UserDefaults.standard.string(forKey: "debug_raw_interface_response") ?? "(open any device detail to populate)")
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
                #endif
            }
            .navigationTitle("Settings")
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
                // Find which saved connection matches current @AppStorage credentials
                if let match = savedConnections.first(where: {
                    $0.baseURL == baseURL &&
                    $0.apiKey  == apiKey  &&
                    $0.pin     == pin     &&
                    $0.ackUser == ackUser
                }) {
                    activeSavedID = match.id
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
                        id: activeSavedID ?? UUID(),
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
                    activeSavedID = now.id

                    // Write to @AppStorage (triggers ContentView.updateAPIService via onChange)
                    baseURL  = now.baseURL
                    apiKey   = now.apiKey
                    pin      = now.pin
                    ackUser  = now.ackUser

                    alertTitle   = "Connection successful"
                    alertMessage = "Connected — \(deviceCount) device\(deviceCount == 1 ? "" : "s") found. '\(now.name)' saved."
                } else {
                    alertTitle   = "Connected — no devices found"
                    alertMessage = "The server responded successfully but returned no devices.\n\nCheck that your API key has permission to list devices."
                }
            case 401, 403:
                alertTitle = "Authentication failed"
                alertMessage = "HTTP \(statusCode): The server rejected the credentials.\n\nCheck your API key and PIN."
            case 404:
                alertTitle = "Endpoint not found"
                alertMessage = "HTTP 404: The API endpoint was not found.\n\nCheck the base URL."
            case 500...599:
                alertTitle = "Server error"
                alertMessage = "HTTP \(statusCode): The server reported an internal error."
            default:
                let bodyPreview = String(data: data.prefix(300), encoding: .utf8) ?? "(unreadable)"
                alertTitle = "Unexpected response"
                alertMessage = "HTTP \(statusCode)\n\nResponse: \(bodyPreview)"
            }
        } catch let urlError as URLError {
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
            alertTitle = "Error"
            alertMessage = error.localizedDescription
        }

        showingAlert = true
    }

    private func selectConnection(_ connection: SavedConnection) {
        draftName    = connection.name
        draftBaseURL = connection.baseURL
        draftApiKey  = connection.apiKey
        draftPin     = connection.pin
        draftAckUser = connection.ackUser
        activeSavedID = connection.id
        Task { await testConnection() }
    }

    private func selectNewConnection() {
        draftName    = "New Server"
        draftBaseURL = ""
        draftApiKey  = ""
        draftPin     = ""
        draftAckUser = ""
        activeSavedID = nil
    }

    private func deleteActiveConnection() {
        guard let id = activeSavedID else { return }
        savedConnections.removeAll { $0.id == id }
        UserDefaults.standard.saveSavedConnections(savedConnections)
        activeSavedID = nil
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