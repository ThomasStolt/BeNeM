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
    /// Set when the alert is the SUCCESS confirmation, so OK returns to Settings.
    @State private var dismissAfterAlert       = false
    @State private var showingDeleteConfirm    = false

    @State private var savedConnections: [SavedConnection] = []

    private enum TestStatus { case untested, success, failure }
    private enum Field: Hashable { case name, bhnmURL, apiKey, pin, ackUser, middlewareURL, pushSecret }
    @FocusState private var focusedField: Field?

    @Environment(\.dismiss) private var dismiss

    private var isAddMode: Bool { existingConnection == nil }

    /// Delegated to `ServerDraft.saveDisabled` so the rule is testable — see
    /// BeNeMTests/ServerDraftTests.swift. Deliberately NOT disabled when nothing has
    /// changed: Save is also the only way to re-run the connection probe.
    private var saveDisabled: Bool {
        currentDraft.saveDisabled(isAddMode: isAddMode, isTesting: isTesting)
    }

    private var currentDraft: ServerDraft {
        ServerDraft(name: draftName, middlewareURL: draftMiddlewareURL, bhnmURL: draftBhnmURL,
                    apiKey: draftApiKey, pin: draftPin, ackUser: draftAckUser,
                    pushSecret: draftPushSecret,
                    notificationsEnabled: draftNotificationsEnabled,
                    symbol: draftSymbol, accentColor: draftColor)
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
                LabeledField("Middleware URL", placeholder: "https://bhnm-apns.yourcompany.com") {
                    TextField("", text: $draftMiddlewareURL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .focused($focusedField, equals: .middlewareURL)
                }
                LabeledField("API Token", placeholder: "Required") {
                    SecureField("", text: $draftApiKey)
                        .focused($focusedField, equals: .apiKey)
                }
                secretHint(draftApiKey)
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

                LabeledField("Webhook Secret", placeholder: "Required for push") {
                    SecureField("", text: $draftPushSecret)
                        .focused($focusedField, equals: .pushSecret)
                        .disabled(!draftNotificationsEnabled)
                }
                .opacity(draftNotificationsEnabled ? 1 : 0.4)
                if draftNotificationsEnabled {
                    secretHint(draftPushSecret)
                    if draftPushSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Push is on but no webhook secret is stored, so this server "
                             + "cannot deliver notifications until one is entered.")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .listRowSeparator(.hidden)
                    }
                }
            }

            // Status row
            if testStatus != .untested {
                Section {
                    HStack {
                        Spacer()
                        if testStatus == .success {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            Text("Connection successful").foregroundColor(.green)
                        } else {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                            Text("Connection failed").foregroundColor(.red)
                        }
                        Spacer()
                    }
                    .font(.subheadline)
                }
            }

            // Actions
            Section {
                if isTesting {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding(.vertical, 4)
                        Spacer()
                    }
                } else {
                    HStack(spacing: 0) {
                        // Save button
                        Button {
                            Task { await testAndSave() }
                        } label: {
                            HStack(spacing: 6) {
                                FloppyDiskIcon()
                                    .frame(width: 18, height: 18)
                                Text(isAddMode ? "Test & Save" : "Save")
                            }
                            .frame(maxWidth: .infinity)
                            .foregroundColor(saveDisabled ? .gray : .green)
                        }
                        .buttonStyle(.plain)
                        .disabled(saveDisabled)

                        // Delete button
                        if !isAddMode {
                            Divider().frame(height: 28)

                            Button {
                                showingDeleteConfirm = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "trash.fill")
                                    Text("Delete")
                                }
                                .frame(maxWidth: .infinity)
                                .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .onTapGesture { focusedField = nil }
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
            Button("OK", role: .cancel) { if dismissAfterAlert { dismiss() } }
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

    /// The stored value's tail, so a stored secret can be told apart from another
    /// during troubleshooting without ever displaying it. `SecureField` shows dots
    /// while typing and nothing at all afterwards, which is why this exists.
    @ViewBuilder
    private func secretHint(_ value: String) -> some View {
        HStack {
            Text("Stored:")
            Text(ServerDraft.maskedSecret(value)).fontDesign(.monospaced)
            Spacer()
        }
        .font(.caption2)
        .foregroundColor(.secondary)
        .listRowSeparator(.hidden)
    }

    // MARK: - Secret display

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

        // Always normalize middleware URL (required for all connections)
        let mwURLStringRaw = draftMiddlewareURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mwURLStringRaw.isEmpty else {
            testStatus = .failure
            alertTitle = "Middleware URL Required"
            alertMessage = "Enter the Middleware URL before saving. All API calls route through the middleware."
            showingAlert = true
            return
        }
        var mwURLString = mwURLStringRaw
        if !mwURLString.hasPrefix("http://") && !mwURLString.hasPrefix("https://") {
            mwURLString = "https://\(mwURLString)"
        }
        draftMiddlewareURL = mwURLString

        guard let mwURLParsed = URL(string: mwURLString), mwURLParsed.host != nil else {
            testStatus = .failure
            alertTitle = "Invalid URL"
            alertMessage = "Could not parse \"\(mwURLString)\" as a middleware URL."
            showingAlert = true
            return
        }

        let testBase = mwURLString.trimmingSuffix("/")

        guard let bhnmURLParsed = URL(string: bhnmURLString), bhnmURLParsed.host != nil else {
            testStatus = .failure
            alertTitle = "Invalid URL"
            alertMessage = "Could not parse \"\(bhnmURLString)\" as a URL."
            showingAlert = true
            return
        }

        guard let testURL = URL(string: "\(testBase)/api/incident_api.php") else {
            testStatus = .failure
            alertTitle = "Invalid URL"
            alertMessage = "Could not construct test endpoint."
            showingAlert = true
            return
        }

        var request = URLRequest(url: testURL, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue(bhnmURLString, forHTTPHeaderField: "X-BHNM-Target")
        // The api_key IS the proxy token — the same value the runtime path sends
        // (ContentView.swift:198 -> NetreoAPIService.swift:57). One behaviour for one thing.
        //
        // This used to send draftPushSecret, and it only ever worked because the
        // deployment had PROXY_TOKEN and WEBHOOK_SECRET set to the same value. When
        // PROXY_TOKEN was rotated on 2026-09-17 the probe began returning 401 — and
        // since saveConnection() runs only on a 200, that discarded the user's edit.
        // See docs/evidence/2026-09-17-2.17.0-deploy-record.md section 6.
        if !draftApiKey.isEmpty {
            request.setValue(draftApiKey, forHTTPHeaderField: "X-Proxy-Token")
        }
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // A deliberately unsupported method. BHNM checks the credential BEFORE the
        // method, so this answers "is the key good" in a CONSTANT 51 bytes, whatever
        // the size of the estate — measured 2026-09-18:
        //   wrong key   -> {"result":"error","detail":"Password failed."}        46 B
        //   good key    -> {"result":"error","detail":"Method not supported."}   51 B
        // getincidents would answer the same question in ~209 bytes per incident,
        // about 204 KB at n=1000, and neither `limit` nor `count` bounds it.
        var bodyItems = [URLQueryItem(name: "pwd", value: draftApiKey),
                         URLQueryItem(name: "method", value: "benem_connection_check")]
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
                // BHNM answers 200 for everything, so the body carries the verdict.
                switch probeVerdict(data) {
                case .verified:
                    saveConnection(bhnmURLString: bhnmURLString)
                    testStatus = .success
                    alertTitle = "Connection verified"
                    // The PIN is NOT listed as uncovered: it is sent when one is entered,
                    // and BHNM checks credentials before the method, so a wrong PIN fails
                    // this probe exactly as a wrong key does.
                    alertMessage = "BHNM is reachable through the middleware and accepted the credentials."
                    dismissAfterAlert = true
                    showingAlert = true

                case .authFailed(let detail):
                    // BHNM never says WHICH credential it rejected, so the app must not
                    // either. The form knows whether a PIN was entered, so it can point
                    // at the right field instead of making the user work out whether
                    // they are on SaaS.
                    testStatus = .failure
                    alertTitle = "Authentication failed"
                    alertMessage = "BHNM rejected these credentials: \"\(detail)\"\n\n"
                        + (draftPin.isEmpty
                           ? "Check the API key. SaaS servers also require a PIN."
                           : "Check the API key and the PIN.")
                    showingAlert = true

                case .inconclusive(let preview):
                    testStatus = .failure
                    alertTitle = "Could not verify"
                    alertMessage = "The server answered, but not in a way this app recognises, "
                        + "so the connection is NOT verified and nothing was saved.\n\n"
                        + "It said:\n\(preview)"
                    showingAlert = true
                }
            // 401 and 403 mean different things now that the api_key is the proxy
            // token. One message for both named the wrong cause for half of them.
            case 401:
                testStatus = .failure; alertTitle = "Authentication failed"
                alertMessage = "HTTP 401: Check your API key and PIN."
                showingAlert = true
            case 403:
                testStatus = .failure; alertTitle = "Server not allowed"
                alertMessage = "HTTP 403: The middleware refused this BHNM URL for this API key.\n\n"
                    + "Check the BHNM URL — it must be a server the middleware is configured for "
                    + "and the one this API key belongs to."
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

    /// What the probe proved. THREE outcomes, never two: a reply this app does not
    /// recognise is INCONCLUSIVE, not a pass.
    ///
    /// The old rule — "a password error is the one failure, anything else is a pass" —
    /// treated an unrecognised reply as success and hung the whole verdict on BHNM's
    /// exact wording of "Password failed.". If that string ever changed, a WRONG KEY
    /// would have read as a good connection. The failure direction now runs the safe
    /// way: a wording change degrades to "could not verify", never to a false pass.
    private enum ProbeVerdict {
        case verified
        case authFailed(String)
        case inconclusive(String)
    }

    /// Matching is on structure first and on the narrowest possible words second,
    /// because BHNM's API carries no error code — only `result` and a human `detail`.
    ///
    ///  - `result: "completed"`  — structural. BHNM did work, so the key was accepted.
    ///  - detail mentions a credential — checked FIRST, so an auth error can never be
    ///    read as anything else.
    ///  - detail mentions the METHOD — the method is the thing we deliberately got
    ///    wrong, and BHNM checks the credential BEFORE the method, so any complaint
    ///    about the method necessarily happened after the key was accepted. Matching
    ///    the word rather than the sentence covers "Method not supported.",
    ///    "Missing method in your request." and "Missing required information for
    ///    this method." — all three observed 2026-09-18.
    ///  - anything else, including a body with no `result` key — inconclusive.
    private func probeVerdict(_ data: Data) -> ProbeVerdict {
        let preview = String(data: data.prefix(300), encoding: .utf8) ?? "<non-UTF8 response>"
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let result = json["result"] as? String else {
            return .inconclusive(preview)
        }
        let detail = (json["detail"] as? String) ?? ""

        if detail.localizedCaseInsensitiveContains("password")
            || detail.localizedCaseInsensitiveContains("credential") {
            return .authFailed(detail)
        }
        if result.caseInsensitiveCompare("completed") == .orderedSame {
            return .verified
        }
        if detail.localizedCaseInsensitiveContains("method") {
            return .verified
        }
        return .inconclusive(preview)
    }

    private func saveConnection(bhnmURLString: String) {
        let now = currentDraft.connection(id: existingConnection?.id ?? UUID(),
                                          bhnmURLString: bhnmURLString)

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
