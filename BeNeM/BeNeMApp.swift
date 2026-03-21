import SwiftUI

@main
struct BeNeMApp: App {
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
        }
    }
}
