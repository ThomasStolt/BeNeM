import SwiftUI

@main
struct BeNeMApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var deepLinkHandler = DeepLinkHandler()
    @State private var showSplash = true

    init() {
        migrateLegacyKeysToSavedConnectionIfNeeded()
    }

    /// If the user configured a server before the multi-server redesign, the credentials live in
    /// individual AppStorage keys but there may be no SavedConnection in UserDefaults. Create one
    /// so the server appears in the list and the app continues to function correctly.
    private func migrateLegacyKeysToSavedConnectionIfNeeded() {
        let ud = UserDefaults.standard
        guard let url = ud.string(forKey: "netreo_base_url"), !url.isEmpty,
              let key = ud.string(forKey: "netreo_api_key"), !key.isEmpty else { return }
        var connections = ud.loadSavedConnections()
        // Only migrate if there is no connection matching this URL already
        guard !connections.contains(where: { $0.baseURL.lowercased() == url.lowercased() }) else { return }
        let pin     = ud.string(forKey: "netreo_pin") ?? ""
        let ackUser = ud.string(forKey: "netreo_ack_user") ?? ""
        let name    = URL(string: url)?.host ?? url
        let newConn = SavedConnection(
            id: UUID(),
            name: name,
            baseURL: url,
            apiKey: key,
            pin: pin,
            ackUser: ackUser
        )
        connections.append(newConn)
        ud.saveSavedConnections(connections)
        // Mark as active so ContentView continues using these credentials
        ud.set(newConn.id.uuidString, forKey: "netreo_active_connection_id")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .overlay {
                    if showSplash {
                        SplashView {
                            showSplash = false
                        }
                    }
                }
                .onOpenURL { url in
                    deepLinkHandler.handle(url: url)
                }
                .alert(
                    "Apply Configuration?",
                    isPresented: Binding(
                        get: { deepLinkHandler.pendingImport != nil },
                        set: { if !$0 { deepLinkHandler.pendingImport = nil } }
                    )
                ) {
                    Button("Apply") { deepLinkHandler.applyPendingImport() }
                    Button("Cancel", role: .cancel) { deepLinkHandler.pendingImport = nil }
                } message: {
                    if let imp = deepLinkHandler.pendingImport {
                        Text("Server: \(imp.serverURL)\nUser: \(imp.ackUser)")
                    }
                }
                .alert(
                    "Invalid Link",
                    isPresented: Binding(
                        get: { deepLinkHandler.importError != nil },
                        set: { if !$0 { deepLinkHandler.importError = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) {}
                } message: {
                    if let error = deepLinkHandler.importError {
                        Text(error)
                    }
                }
        }
    }
}
