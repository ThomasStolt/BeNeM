import SwiftUI

@main
struct BeNeMApp: App {
    @StateObject private var deepLinkHandler = DeepLinkHandler()
    @State private var showSplash = true

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
                    Text(deepLinkHandler.importError ?? "")
                }
        }
    }
}
