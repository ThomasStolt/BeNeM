// BeNeM/Views/ServerConfigView.swift
import SwiftUI

struct ServerConfigView: View {
    let existingConnection: SavedConnection?

    @AppStorage("netreo_base_url")              private var storedMiddlewareURL = ""
    @AppStorage("netreo_bhnm_url")              private var storedBhnmURL = ""
    @AppStorage("netreo_api_key")               private var apiKey = ""
    @AppStorage("netreo_pin")                   private var pin = ""
    @AppStorage("netreo_ack_user")              private var ackUser = ""
    @AppStorage("netreo_active_connection_id")  private var activeSavedConnectionID = ""

    // Draft state — Connection section
    @State private var draftName       = ""
    @State private var draftBhnmURL    = ""
    @State private var draftApiKey     = ""
    @State private var draftPin        = ""
    @State private var draftAckUser    = ""
    @State private var draftSymbol     = "server.rack"
    @State private var draftColor      = "#0A84FF"

    // Draft state — Push Notifications section
    @State private var draftNotificationsEnabled = true
    @State private var draftMiddlewareURL        = ""
    @State private var draftPushSecret           = ""

    @State private var showingIconPicker       = false
    @State private var isTesting               = false
    @State private var testStatus: TestStatus  = .untested
    @State private var alertTitle              = ""
    @State private var alertMessage            = ""
    @State private var showingAlert            = false
    @State private var showingDeleteConfirm    = false

    @State private var savedConnections: [SavedConnection] = []

    private enum TestStatus { case untested, success, failure }
    private enum Field: Hashable { case name, bhnmURL, apiKey, pin, ackUser, middlewareURL, pushSecret }
    @FocusState private var focusedField: Field?

    @Environment(\.dismiss) private var dismiss

    private var isAddMode: Bool { existingConnection == nil }

    // Save button disabled when required fields are empty
    private var saveDisabled: Bool {
        isTesting
        || draftName.isEmpty
        || draftBhnmURL.isEmpty
        || draftApiKey.isEmpty
        || draftAckUser.isEmpty
        || (draftNotificationsEnabled && (draftMiddlewareURL.isEmpty || draftPushSecret.isEmpty))
    }

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

            // Connection section
            Section("Connection") {
                LabeledField("Server Name", placeholder: "e.g. Production BHNM") {
                    TextField("", text: $draftName)
                        .focused($focusedField, equals: .name)
                }
                LabeledField("BHNM URL", placeholder: "https://bhnm.yourcompany.com") {
                    TextField("", text: $draftBhnmURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .focused($focusedField, equals: .bhnmURL)
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

            // Push Notifications section
            Section("Push Notifications") {
                Toggle("Enable Push Notifications", isOn: $draftNotificationsEnabled)

                LabeledField("Middleware URL", placeholder: "https://bhnm-apns.yourcompany.com") {
                    TextField("", text: $draftMiddlewareURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .focused($focusedField, equals: .middlewareURL)
                        .disabled(!draftNotificationsEnabled)
                }
                .opacity(draftNotificationsEnabled ? 1 : 0.4)

                LabeledField("Webhook Secret", placeholder: "Required for push") {
                    SecureField("", text: $draftPushSecret)
                        .focused($focusedField, equals: .pushSecret)
                        .disabled(!draftNotificationsEnabled)
                }
                .opacity(draftNotificationsEnabled ? 1 : 0.4)
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
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text(isAddMode ? "Test & Save" : "Save")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .disabled(saveDisabled)

                if !isAddMode {
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Text("Delete Server").frame(maxWidth: .infinity)
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
            draftName                 = conn.name
            draftBhnmURL              = conn.bhnmURL
            draftApiKey               = conn.apiKey
            draftPin                  = conn.pin
            draftAckUser              = conn.ackUser
            draftSymbol               = conn.symbol
            draftColor                = conn.accentColor
            draftNotificationsEnabled = conn.notificationsEnabled
            draftMiddlewareURL        = conn.middlewareURL
            draftPushSecret           = conn.webhookSecret
        }
    }

    @MainActor
    private func testAndSave() async {
        focusedField = nil
        isTesting = true
        defer { isTesting = false }

        // Normalize BHNM URL
        var bhnmURLString = draftBhnmURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !bhnmURLString.hasPrefix("http://") && !bhnmURLString.hasPrefix("https://") {
            bhnmURLString = "https://\(bhnmURLString)"
        }
        draftBhnmURL = bhnmURLString

        // Normalize middleware URL if push is enabled
        if draftNotificationsEnabled {
            var mw = draftMiddlewareURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if !mw.isEmpty, !mw.hasPrefix("http://"), !mw.hasPrefix("https://") {
                mw = "https://\(mw)"
            }
            draftMiddlewareURL = mw
        }

        guard let bhnmURLParsed = URL(string: bhnmURLString), bhnmURLParsed.host != nil else {
            testStatus = .failure
            alertTitle = "Invalid URL"
            alertMessage = "Could not parse \"\(bhnmURLString)\" as a URL."
            showingAlert = true
            return
        }

        // Build test URL and request
        let testBase: String
        let addProxyHeaders: Bool
        if draftNotificationsEnabled && !draftMiddlewareURL.isEmpty {
            testBase = draftMiddlewareURL.trimmingSuffix("/")
            addProxyHeaders = true
        } else {
            testBase = bhnmURLString.trimmingSuffix("/")
            addProxyHeaders = false
        }

        guard let testURL = URL(string: "\(testBase)/fw/index.php?r=restful/devices/list") else {
            testStatus = .failure
            alertTitle = "Invalid URL"
            alertMessage = "Could not construct test endpoint."
            showingAlert = true
            return
        }

        var request = URLRequest(url: testURL, timeoutInterval: 15)
        request.httpMethod = "POST"
        if addProxyHeaders {
            request.setValue(draftPushSecret, forHTTPHeaderField: "X-Proxy-Token")
            request.setValue(bhnmURLString, forHTTPHeaderField: "X-BHNM-Target")
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
            guard let httpResponse = response as? HTTPURLResponse else {
                testStatus = .failure; alertTitle = "Error"
                alertMessage = "Unexpected response type."
                showingAlert = true
                return
            }
            let statusCode = httpResponse.statusCode

            switch statusCode {
            case 200:
                var deviceCount = 0
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let arr = json["devices"] as? [[String: Any]] { deviceCount = arr.count }
                    else if let nested = json["data"] as? [String: Any],
                            let arr = nested["devices"] as? [[String: Any]] { deviceCount = arr.count }
                }
                if deviceCount > 0 {
                    saveConnection(bhnmURLString: bhnmURLString)
                    testStatus = .success
                    dismiss()
                } else {
                    let preview = String(data: data.prefix(300), encoding: .utf8) ?? "<non-UTF8>"
                    testStatus = .failure
                    alertTitle = "Connected — no devices found"
                    alertMessage = "Server responded but returned no devices.\n\nRaw response:\n\(preview)"
                    showingAlert = true
                }
            case 401, 403:
                testStatus = .failure; alertTitle = "Authentication failed"
                alertMessage = "HTTP \(statusCode): Check your API key and PIN."
                showingAlert = true
            case 404:
                testStatus = .failure; alertTitle = "Endpoint not found"
                alertMessage = "HTTP 404: Check the BHNM URL."
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
            case .cannotFindHost:
                alertMessage = "Host not found: \"\(bhnmURLParsed.host ?? bhnmURLString)\"."
            case .cannotConnectToHost:
                alertMessage = "Cannot connect to \"\(bhnmURLParsed.host ?? bhnmURLString)\"."
            case .timedOut: alertMessage = "Timed out after 15 seconds."
            default: alertMessage = urlError.localizedDescription
            }
            showingAlert = true
        } catch {
            testStatus = .failure; alertTitle = "Error"
            alertMessage = error.localizedDescription; showingAlert = true
        }
    }

    private func saveConnection(bhnmURLString: String) {
        let trimmedName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        let middlewareURL = draftNotificationsEnabled
            ? draftMiddlewareURL.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let webhookSecret = draftNotificationsEnabled
            ? draftPushSecret.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""

        let now = SavedConnection(
            id: existingConnection?.id ?? UUID(),
            name: trimmedName.isEmpty ? "Unnamed" : trimmedName,
            middlewareURL: middlewareURL,
            bhnmURL: bhnmURLString,
            notificationsEnabled: draftNotificationsEnabled,
            apiKey: draftApiKey,
            pin: draftPin,
            ackUser: draftAckUser,
            webhookSecret: webhookSecret,
            symbol: draftSymbol,
            accentColor: draftColor
        )

        if let idx = savedConnections.firstIndex(where: { $0.id == now.id }) {
            savedConnections[idx] = now
        } else {
            savedConnections.append(now)
        }
        UserDefaults.standard.saveSavedConnections(savedConnections)

        // Sync to active AppStorage keys if this is the active server
        let isCurrentlyActive = existingConnection?.id.uuidString == activeSavedConnectionID

        // Unregister push if the active connection is switching notifications off
        let wasNotificationsEnabled = existingConnection?.notificationsEnabled ?? false
        if isCurrentlyActive && wasNotificationsEnabled && !draftNotificationsEnabled,
           let token = AppDelegate.shared?.cachedDeviceToken,
           let oldConn = existingConnection {
            AppDelegate.shared?.unregisterWithMiddleware(
                token: token,
                secret: oldConn.webhookSecret,
                middlewareURL: oldConn.middlewareURL
            )
        }

        if isAddMode || isCurrentlyActive {
            activeSavedConnectionID = now.id.uuidString
            storedMiddlewareURL = now.middlewareURL
            storedBhnmURL       = now.bhnmURL
            apiKey              = now.apiKey
            pin                 = now.pin
            ackUser             = now.ackUser
            UserDefaults.standard.set(now.webhookSecret, forKey: "netreo_webhook_secret")
        }
    }

    private func deleteConnection() {
        guard let conn = existingConnection else { return }

        // Unregister push before deleting if this is the active notifications-enabled connection
        if conn.id.uuidString == activeSavedConnectionID,
           conn.notificationsEnabled,
           !conn.middlewareURL.isEmpty,
           let token = AppDelegate.shared?.cachedDeviceToken {
            AppDelegate.shared?.unregisterWithMiddleware(
                token: token,
                secret: conn.webhookSecret,
                middlewareURL: conn.middlewareURL
            )
        }

        savedConnections.removeAll { $0.id == conn.id }
        UserDefaults.standard.saveSavedConnections(savedConnections)
        if activeSavedConnectionID == conn.id.uuidString {
            activeSavedConnectionID = ""
            storedMiddlewareURL = ""
            storedBhnmURL = ""
            apiKey = ""; pin = ""; ackUser = ""
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
