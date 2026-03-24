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
    @State private var draftName = "New BHNM Connection"
    @State private var activeSavedID: UUID? = nil
    @State private var savedConnections: [SavedConnection] = []

    @State private var isTesting = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showingAlert = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Discovery")) {
                    NavigationLink(destination: AutoDiscoveryView()) {
                        Label("Auto Discovery", systemImage: "magnifyingglass.circle.fill")
                    }
                }

                if savedConnections.count >= 2 {
                    Section(header: Text("Connection")) {
                        HStack {
                            Text("Server")
                                .foregroundColor(.secondary)
                            Spacer()
                            Menu {
                                ForEach(savedConnections) { connection in
                                    Button(connection.name) {
                                        // TODO Task 6: selectConnection(connection)
                                    }
                                }
                                Divider()
                                Button("+ New Connection") {
                                    // TODO Task 6: selectNewConnection()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(activeSavedID != nil
                                         ? (savedConnections.first(where: { $0.id == activeSavedID })?.name ?? draftName)
                                         : draftName)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .font(.caption)
                                }
                                .foregroundColor(.primary)
                            }
                        }
                    }
                }

                Section(header: Text("BHNM Server")) {
                    TextField("Connection Name", text: $draftName)
                        .autocapitalization(.none)

                    TextField("Base URL", text: $draftBaseURL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)

                    SecureField("API Key", text: $draftApiKey)

                    SecureField("PIN (SaaS only)", text: $draftPin)

                    TextField("ACK User", text: $draftAckUser)
                        .autocapitalization(.none)

                    HStack(spacing: 0) {
                        Button {
                            Task { await testConnection() }
                        } label: {
                            HStack {
                                if isTesting {
                                    ProgressView().padding(.trailing, 6)
                                    Text("Testing…")
                                } else {
                                    Text("Test Connection")
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .disabled(draftBaseURL.isEmpty || draftApiKey.isEmpty || draftName.isEmpty || isTesting)

                        if activeSavedID != nil {
                            Divider().frame(height: 44)
                            Button(role: .destructive) {
                                // TODO Task 7: showDeleteConfirmation()
                            } label: {
                                Image(systemName: "trash")
                                    .padding(.horizontal, 16)
                            }
                        }
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
            .onAppear {
                draftBaseURL = baseURL
                draftApiKey = apiKey
                draftPin = pin
                draftAckUser = ackUser
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
        }
    }

    @MainActor
    private func testConnection() async {
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