import SwiftUI

struct SettingsView: View {
    @AppStorage("netreo_base_url") private var baseURL = ""
    @AppStorage("netreo_api_key") private var apiKey = ""
    @AppStorage("netreo_pin") private var pin = ""
    @AppStorage("netreo_ack_user") private var ackUser = ""
    @AppStorage("netreo_api_version") private var apiVersionString = "legacy"
    @AppStorage("netreo_timeout") private var timeout: Double = 30.0
    @AppStorage("netreo_retry_count") private var retryCount: Double = 3.0

    @State private var isTesting = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showingAlert = false
    @State private var debugFields: String? = UserDefaults.standard.string(forKey: "debug_incident_fields")

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Netreo Server")) {
                    TextField("Base URL", text: $baseURL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)

                    SecureField("API Key", text: $apiKey)

                    SecureField("PIN (SaaS only)", text: $pin)

                    TextField("ACK User", text: $ackUser)
                        .autocapitalization(.none)
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

                Section(header: Text("Debug: Incident API Felder")) {
                    if let fields = debugFields {
                        Text(fields)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    } else {
                        Text("Noch keine Daten — bitte zuerst den Incidents-Tab öffnen.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Button("Aktualisieren") {
                        debugFields = UserDefaults.standard.string(forKey: "debug_incident_fields")
                    }
                }

                Section(footer: Text("Enter your Netreo server details to connect to your network monitoring system. Choose the appropriate API version based on your Netreo deployment.")) {
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

        // URL validieren
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL), url.scheme != nil, url.host != nil else {
            alertTitle = "Ungültige URL"
            alertMessage = "Die eingegebene URL \"\(trimmedURL)\" ist kein gültiges Format.\n\nBeispiel: https://netreo.example.com"
            showingAlert = true
            return
        }

        // Tatsächlichen HTTP-Request absetzen
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
                alertTitle = "Verbindung erfolgreich"
                alertMessage = "Der Server hat mit HTTP \(statusCode) geantwortet.\n\nURL: \(testURL.absoluteString)"
            case 401, 403:
                alertTitle = "Authentifizierung fehlgeschlagen"
                alertMessage = "HTTP \(statusCode): Der Server hat die Anfrage abgelehnt.\n\nMögliche Ursachen:\n• API Key ungültig oder abgelaufen\n• PIN fehlt oder falsch (SaaS)\n• Falscher API-Version-Typ\n\nAntwort: \(bodyPreview)"
            case 404:
                alertTitle = "Endpunkt nicht gefunden"
                alertMessage = "HTTP 404: Der API-Endpunkt wurde nicht gefunden.\n\nURL: \(testURL.absoluteString)\n\nMögliche Ursachen:\n• Falsche API-Version ausgewählt\n• Base URL enthält einen falschen Pfad"
            case 500...599:
                alertTitle = "Serverfehler"
                alertMessage = "HTTP \(statusCode): Der Server hat einen internen Fehler gemeldet.\n\nAntwort: \(bodyPreview)"
            default:
                alertTitle = "Unerwartete Antwort"
                alertMessage = "HTTP \(statusCode)\n\nURL: \(testURL.absoluteString)\nAntwort: \(bodyPreview)"
            }
        } catch let urlError as URLError {
            alertTitle = "Verbindung fehlgeschlagen"
            switch urlError.code {
            case .notConnectedToInternet:
                alertMessage = "Kein Internet: Das Gerät ist nicht mit dem Netzwerk verbunden."
            case .cannotFindHost:
                alertMessage = "Host nicht gefunden: Der Server \"\(url.host ?? trimmedURL)\" konnte nicht aufgelöst werden.\n\nMögliche Ursachen:\n• VPN nicht verbunden (falls interner Server)\n• Hostname falsch geschrieben\n• DNS nicht erreichbar"
            case .cannotConnectToHost:
                alertMessage = "Keine Verbindung zum Host: \"\(url.host ?? trimmedURL)\" Port \(url.port.map(String.init) ?? "Standard") ist nicht erreichbar.\n\nMögliche Ursachen:\n• VPN nicht verbunden (falls interner Server)\n• Server läuft nicht\n• Falscher Port\n• Firewall blockiert die Verbindung"
            case .timedOut:
                alertMessage = "Timeout: Der Server hat innerhalb von \(Int(min(timeout, 15))) Sekunden nicht geantwortet.\n\nURL: \(testURL.absoluteString)"
            case .secureConnectionFailed, .serverCertificateUntrusted:
                alertMessage = "SSL/TLS-Fehler: Das Zertifikat des Servers ist ungültig oder nicht vertrauenswürdig.\n\nDetails: \(urlError.localizedDescription)"
            default:
                alertMessage = "\(urlError.localizedDescription)\n\n(Code: \(urlError.code.rawValue))"
            }
        } catch {
            alertTitle = "Fehler"
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