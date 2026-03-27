// BeNeM/Views/ServerConfigView.swift
import SwiftUI

struct ServerConfigView: View {
    // nil = add mode; non-nil = edit mode
    let existingConnection: SavedConnection?

    @AppStorage("netreo_base_url")              private var baseURL = ""
    @AppStorage("netreo_api_key")               private var apiKey = ""
    @AppStorage("netreo_pin")                   private var pin = ""
    @AppStorage("netreo_ack_user")              private var ackUser = ""
    @AppStorage("netreo_active_connection_id")  private var activeSavedConnectionID = ""

    // Draft state
    @State private var draftName       = ""
    @State private var draftBaseURL    = ""
    @State private var draftApiKey     = ""
    @State private var draftPin        = ""
    @State private var draftAckUser    = ""
    @State private var draftSymbol     = "server.rack"
    @State private var draftColor      = "#0A84FF"
    @State private var draftPushSecret = ""

    @State private var showingIconPicker       = false
    @State private var isTesting               = false
    @State private var testStatus: TestStatus  = .untested
    @State private var alertTitle              = ""
    @State private var alertMessage            = ""
    @State private var showingAlert            = false
    @State private var showingDeleteConfirm    = false

    @State private var savedConnections: [SavedConnection] = []

    private enum TestStatus { case untested, success, failure }
    private enum Field: Hashable { case name, url, apiKey, pin, ackUser, pushSecret }
    @FocusState private var focusedField: Field?

    @Environment(\.dismiss) private var dismiss

    private var isAddMode: Bool { existingConnection == nil }
    private var activeID: UUID? { UUID(uuidString: activeSavedConnectionID) }

    var body: some View {
        Form {
            // Icon header
            Section {
                VStack(spacing: 6) {
                    Button {
                        showingIconPicker = true
                    } label: {
                        VStack(spacing: 6) {
                            ServerIconView(symbol: draftSymbol, accentColor: draftColor, size: 72)
                                .shadow(color: Color(hex: draftColor).opacity(0.35), radius: 8, y: 4)
                            Text("Tap to customise")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            // Connection fields
            Section("Connection") {
                LabeledField("Server Name", placeholder: "e.g. Production BHNM") {
                    TextField("", text: $draftName)
                        .focused($focusedField, equals: .name)
                }
                LabeledField("Middleware URL", placeholder: "https://bhnm-apns.yourcompany.com") {
                    TextField("", text: $draftBaseURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .focused($focusedField, equals: .url)
                }
                LabeledField("API Token", placeholder: "Required") {
                    SecureField("", text: $draftApiKey)
                        .focused($focusedField, equals: .apiKey)
                }
                LabeledField("PIN / License ID", placeholder: "SaaS only") {
                    SecureField("", text: $draftPin)
                        .focused($focusedField, equals: .pin)
                }
                LabeledField("User Name", placeholder: "Required") {
                    TextField("", text: $draftAckUser)
                        .autocapitalization(.none)
                        .focused($focusedField, equals: .ackUser)
                }
            }

            // Push notifications
            Section("Push Notifications") {
                LabeledField("Webhook Secret", placeholder: "Required for middleware connection") {
                    SecureField("", text: $draftPushSecret)
                        .focused($focusedField, equals: .pushSecret)
                }
                Text("Enter the webhook secret configured in your middleware's .env file.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Actions
            Section {
                Button {
                    Task { await testAndSave() }
                } label: {
                    HStack {
                        if testStatus == .success {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        } else if testStatus == .failure {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                        }
                        if isTesting {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text(isAddMode ? "Test & Save" : "Save")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .disabled(isTesting || draftBaseURL.isEmpty || draftApiKey.isEmpty || draftName.isEmpty || draftAckUser.isEmpty || draftPushSecret.isEmpty)

                if !isAddMode {
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Text("Delete Server")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationTitle(isAddMode ? "Add Server" : draftName)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.immediately)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button { focusedField = nil } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                }
            }
        }
        .sheet(isPresented: $showingIconPicker) {
            IconPickerSheet(symbol: $draftSymbol, accentColor: $draftColor)
        }
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
        .alert("Delete \"\(draftName)\"?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteConnection() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This server will be removed from your saved list.")
        }
        .onAppear { populateDrafts() }
    }

    // MARK: - Helpers

    private func populateDrafts() {
        savedConnections = UserDefaults.standard.loadSavedConnections()
        if let conn = existingConnection {
            draftName       = conn.name
            draftBaseURL    = conn.middlewareURL
            draftApiKey     = conn.apiKey
            draftPin        = conn.pin
            draftAckUser    = conn.ackUser
            draftSymbol     = conn.symbol
            draftColor      = conn.accentColor
            draftPushSecret = conn.webhookSecret
        }
    }

    @MainActor
    private func testAndSave() async {
        focusedField = nil
        isTesting = true
        defer { isTesting = false }

        // Auto-prepend https:// if no scheme
        var urlString = draftBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://\(urlString)"
        }
        draftBaseURL = urlString

        guard let url = URL(string: urlString), url.host != nil else {
            testStatus = .failure
            alertTitle = "Invalid URL"
            alertMessage = "Could not parse \"\(urlString)\" as a URL."
            showingAlert = true
            return
        }

        guard let testURL = URL(string: "\(urlString.trimmingSuffix("/"))/fw/index.php?r=restful/devices/list") else {
            testStatus = .failure
            alertTitle = "Invalid URL"
            alertMessage = "Could not construct test endpoint."
            showingAlert = true
            return
        }

        var request = URLRequest(url: testURL, timeoutInterval: 15)
        request.httpMethod = "POST"
        if !draftPushSecret.isEmpty {
            request.setValue(draftPushSecret, forHTTPHeaderField: "X-Proxy-Token")
        }
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyItems = [URLQueryItem(name: "password", value: draftApiKey)]
        if !draftPin.isEmpty { bodyItems.append(URLQueryItem(name: "pin", value: draftPin)) }
        var comps = URLComponents()
        comps.queryItems = bodyItems
        request.httpBody = comps.percentEncodedQuery?.data(using: .utf8)

        do {
            let sessionConfig = URLSessionConfiguration.default
            sessionConfig.timeoutIntervalForRequest = 15
            let (data, response) = try await URLSession(configuration: sessionConfig).data(for: request)
            let statusCode = (response as! HTTPURLResponse).statusCode

            switch statusCode {
            case 200:
                var deviceCount = 0
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let arr = json["devices"] as? [[String: Any]] { deviceCount = arr.count }
                    else if let nested = json["data"] as? [String: Any],
                            let arr = nested["devices"] as? [[String: Any]] { deviceCount = arr.count }
                }
                if deviceCount > 0 {
                    saveConnection(urlString: urlString)
                    testStatus = .success
                    dismiss()
                } else {
                    testStatus = .failure
                    alertTitle = "Connected — no devices found"
                    alertMessage = "Server responded but returned no devices. Check API key permissions."
                    showingAlert = true
                }
            case 401, 403:
                testStatus = .failure; alertTitle = "Authentication failed"
                alertMessage = "HTTP \(statusCode): Check your API key and PIN."
                showingAlert = true
            case 404:
                testStatus = .failure; alertTitle = "Endpoint not found"
                alertMessage = "HTTP 404: Check the base URL."
                showingAlert = true
            default:
                testStatus = .failure; alertTitle = "Unexpected response"
                alertMessage = "HTTP \(statusCode)"
                showingAlert = true
            }
        } catch let urlError as URLError {
            testStatus = .failure
            alertTitle = "Connection failed"
            switch urlError.code {
            case .notConnectedToInternet: alertMessage = "No internet connection."
            case .cannotFindHost: alertMessage = "Host not found: \"\(url.host ?? urlString)\"."
            case .cannotConnectToHost: alertMessage = "Cannot connect to \"\(url.host ?? urlString)\"."
            case .timedOut: alertMessage = "Timed out after 15 seconds."
            default: alertMessage = urlError.localizedDescription
            }
            showingAlert = true
        } catch {
            testStatus = .failure; alertTitle = "Error"
            alertMessage = error.localizedDescription; showingAlert = true
        }
    }

    private func saveConnection(urlString: String) {
        let trimmedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = SavedConnection(
            id: existingConnection?.id ?? UUID(),
            name: trimmedName.isEmpty ? "Unnamed" : trimmedName,
            middlewareURL: urlString,
            bhnmURL: "",
            apiKey: draftApiKey,
            pin: draftPin,
            ackUser: draftAckUser,
            webhookSecret: draftPushSecret.trimmingCharacters(in: .whitespacesAndNewlines),
            symbol: draftSymbol,
            accentColor: draftColor
        )
        if let idx = savedConnections.firstIndex(where: { $0.id == now.id }) {
            savedConnections[idx] = now
        } else {
            savedConnections.append(now)
        }
        UserDefaults.standard.saveSavedConnections(savedConnections)
        // Keep netreo_webhook_secret in sync so ContentView.updateAPIService() fires
        if isAddMode || existingConnection?.id.uuidString == activeSavedConnectionID {
            UserDefaults.standard.set(now.webhookSecret, forKey: "netreo_webhook_secret")
        }
        // Only set as active if: adding a new server, OR editing the currently active server.
        let isCurrentlyActive = existingConnection?.id.uuidString == activeSavedConnectionID
        if isAddMode || isCurrentlyActive {
            activeSavedConnectionID = now.id.uuidString
            baseURL  = now.middlewareURL
            apiKey   = now.apiKey
            pin      = now.pin
            ackUser  = now.ackUser
        }
    }

    private func deleteConnection() {
        guard let conn = existingConnection else { return }
        savedConnections.removeAll { $0.id == conn.id }
        UserDefaults.standard.saveSavedConnections(savedConnections)
        if activeSavedConnectionID == conn.id.uuidString {
            activeSavedConnectionID = ""
            baseURL = ""; apiKey = ""; pin = ""; ackUser = ""
        }
        dismiss()
    }
}

// MARK: - LabeledField helper

private struct LabeledField<Content: View>: View {
    let label: String
    let placeholder: String
    @ViewBuilder let content: () -> Content

    init(_ label: String, placeholder: String = "", @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.placeholder = placeholder
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            content()
        }
        .padding(.vertical, 2)
    }
}
