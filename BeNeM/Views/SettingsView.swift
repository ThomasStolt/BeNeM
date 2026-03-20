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

    @State private var isTesting = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showingAlert = false
    @State private var debugFields: String? = UserDefaults.standard.string(forKey: "debug_incident_fields")
    @State private var debugDeviceFields: String? = UserDefaults.standard.string(forKey: "debug_device_fields")
    @State private var debugUnmatched: String? = UserDefaults.standard.string(forKey: "debug_unmatched_incidents")

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Discovery")) {
                    NavigationLink(destination: AutoDiscoveryView()) {
                        Label("Auto Discovery", systemImage: "magnifyingglass.circle.fill")
                    }
                }

                Section(header: Text("BHNM Server")) {
                    TextField("Base URL", text: $baseURL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)

                    SecureField("API Key", text: $apiKey)

                    SecureField("PIN (SaaS only)", text: $pin)

                    TextField("ACK User", text: $ackUser)
                        .autocapitalization(.none)
                }

                Section(header: Text("Refresh")) {
                    VStack(alignment: .leading) {
                        Text("Auto-Refresh: \(Int(refreshInterval))s")
                        Slider(value: $refreshInterval, in: 30...300, step: 10)
                    }
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

                Section(header: Text("Connection Test")) {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            if isTesting {
                                ProgressView()
                                    .padding(.trailing, 6)
                                Text("Testing…")
                            } else {
                                Text("Test Connection")
                            }
                        }
                    }
                    .disabled(baseURL.isEmpty || apiKey.isEmpty || isTesting)
                }

                Section(header: Text("Debug: Unmatched Incidents")) {
                    if let fields = debugUnmatched {
                        Text(fields)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    } else {
                        Text("None — all incident device names matched.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Button("Refresh") {
                        debugUnmatched = UserDefaults.standard.string(forKey: "debug_unmatched_incidents")
                    }
                }

                Section(header: Text("Debug: Device API Fields")) {
                    if let fields = debugDeviceFields {
                        Text(fields)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    } else {
                        Text("No data yet — open the Dashboard first.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Button("Refresh") {
                        debugDeviceFields = UserDefaults.standard.string(forKey: "debug_device_fields")
                    }
                }

                Section(header: Text("Debug: Incident API Fields")) {
                    if let fields = debugFields {
                        Text(fields)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    } else {
                        Text("No data yet — open the Incidents tab first.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Button("Refresh") {
                        debugFields = UserDefaults.standard.string(forKey: "debug_incident_fields")
                    }
                }

                Section(footer: Text("Enter your BHNM server details to connect to BMC Helix Network Management. Choose the appropriate API version based on your deployment.")) {
                    EmptyView()
                }
            }
            .navigationTitle("Settings")
            .alert(alertTitle, isPresented: $showingAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
    }

    @MainActor
    private func testConnection() async {
        isTesting = true
        defer { isTesting = false }

        // Validate URL
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL), url.scheme != nil, url.host != nil else {
            alertTitle = "Invalid URL"
            alertMessage = "The URL \"\(trimmedURL)\" is not a valid format.\n\nExample: https://netreo.example.com"
            showingAlert = true
            return
        }

        // Send actual HTTP request
        let config = NetreoAPIConfiguration(
            baseURL: trimmedURL,
            apiKey: apiKey,
            pin: pin.isEmpty ? nil : pin,
            version: NetreoAPIConfiguration.APIVersion(rawValue: apiVersionString) ?? .legacy,
            timeout: timeout,
            retryCount: Int(retryCount)
        )

        let testURL: URL
        switch config.version {
        case .legacy:
            testURL = URL(string: config.endpoint(for: "/api.php"))!
        case .v1:
            testURL = URL(string: config.endpoint(for: "/api/v1/devices"))!
        case .v2:
            testURL = URL(string: config.endpoint(for: "/api/v2/devices"))!
        case .openapi:
            testURL = URL(string: config.endpoint(for: "/openapi/devices"))!
        }

        var request = URLRequest(url: testURL, timeoutInterval: min(timeout, 15))
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        switch config.version {
        case .legacy:
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let body = "pwd=\(apiKey)&method=getdevices"
            request.httpBody = body.data(using: .utf8)
        default:
            request.httpMethod = "GET"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            let sessionConfig = URLSessionConfiguration.default
            sessionConfig.timeoutIntervalForRequest = min(timeout, 15)
            let session = URLSession(configuration: sessionConfig)

            let (data, response) = try await session.data(for: request)
            let http = response as! HTTPURLResponse
            let statusCode = http.statusCode
            let bodyPreview = String(data: data.prefix(300), encoding: .utf8) ?? "(nicht lesbar)"

            switch statusCode {
            case 200...299:
                alertTitle = "Connection successful"
                alertMessage = "The server responded with HTTP \(statusCode).\n\nURL: \(testURL.absoluteString)"
            case 401, 403:
                alertTitle = "Authentication failed"
                alertMessage = "HTTP \(statusCode): The server rejected the request.\n\nPossible causes:\n• API key invalid or expired\n• PIN missing or incorrect (SaaS)\n• Wrong API version selected\n\nResponse: \(bodyPreview)"
            case 404:
                alertTitle = "Endpoint not found"
                alertMessage = "HTTP 404: The API endpoint was not found.\n\nURL: \(testURL.absoluteString)\n\nPossible causes:\n• Wrong API version selected\n• Base URL contains an incorrect path"
            case 500...599:
                alertTitle = "Server error"
                alertMessage = "HTTP \(statusCode): The server reported an internal error.\n\nResponse: \(bodyPreview)"
            default:
                alertTitle = "Unexpected response"
                alertMessage = "HTTP \(statusCode)\n\nURL: \(testURL.absoluteString)\nResponse: \(bodyPreview)"
            }
        } catch let urlError as URLError {
            alertTitle = "Connection failed"
            switch urlError.code {
            case .notConnectedToInternet:
                alertMessage = "No internet: The device is not connected to a network."
            case .cannotFindHost:
                alertMessage = "Host not found: The server \"\(url.host ?? trimmedURL)\" could not be resolved.\n\nPossible causes:\n• VPN not connected (if internal server)\n• Hostname misspelled\n• DNS unreachable"
            case .cannotConnectToHost:
                alertMessage = "Cannot connect to host: \"\(url.host ?? trimmedURL)\" port \(url.port.map(String.init) ?? "default") is not reachable.\n\nPossible causes:\n• VPN not connected (if internal server)\n• Server not running\n• Wrong port\n• Firewall blocking the connection"
            case .timedOut:
                alertMessage = "Timeout: The server did not respond within \(Int(min(timeout, 15))) seconds.\n\nURL: \(testURL.absoluteString)"
            case .secureConnectionFailed, .serverCertificateUntrusted:
                alertMessage = "SSL/TLS error: The server certificate is invalid or not trusted.\n\nDetails: \(urlError.localizedDescription)"
            default:
                alertMessage = "\(urlError.localizedDescription)\n\n(Code: \(urlError.code.rawValue))"
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