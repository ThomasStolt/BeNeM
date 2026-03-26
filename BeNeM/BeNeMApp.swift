import SwiftUI

@main
struct BeNeMApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var deepLinkHandler = DeepLinkHandler()
    @State private var showSplash = true

    init() {
        migrateGlobalPushURLIfNeeded()
    }

    private func migrateGlobalPushURLIfNeeded() {
        let ud = UserDefaults.standard
        guard let globalURL = ud.string(forKey: "push_middleware_url"), !globalURL.isEmpty else { return }
        let activeID = ud.string(forKey: "netreo_active_connection_id") ?? ""
        var connections = ud.loadSavedConnections()
        guard let idx = connections.firstIndex(where: { $0.id.uuidString == activeID }),
              connections[idx].pushMiddlewareURL.isEmpty else { return }
        connections[idx].pushMiddlewareURL = globalURL
        ud.saveSavedConnections(connections)
        ud.removeObject(forKey: "push_middleware_url")   // only reached after successful write
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
                        let push = imp.pushMiddlewareURL.isEmpty ? "" : "\nPush: \(imp.pushMiddlewareURL)"
                        Text("Server: \(imp.serverURL)\nUser: \(imp.ackUser)\(push)")
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
