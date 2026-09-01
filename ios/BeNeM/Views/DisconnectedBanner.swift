import SwiftUI

/// Global, hop-aware disconnect banner + pulsing top edge. Driven by the
/// ConnectionMonitor poller. Renders nothing when connected.
/// Reduce-motion → static (no pulse).
struct DisconnectedBanner: View {
    @ObservedObject private var connection = ConnectionMonitor.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        if connection.status == .disconnected {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.red)
                    .frame(height: 3)
                    .opacity(reduceMotion ? 1.0 : (pulsing ? 0.25 : 1.0))
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                            pulsing = true
                        }
                    }
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(message).font(.footnote).fontWeight(.medium)
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.92))
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    /// Names the hop that is actually down. Wording distinction: BHNM-down means
    /// the middleware's cache is actively serving ("cached data"); middleware-down
    /// means only the app's own last-fetched data is on screen ("last known
    /// data") — never claim the middleware cache when the middleware is the
    /// unreachable hop.
    private var message: String {
        switch connection.downHop {
        case .bhnm:
            return "BHNM unreachable · showing cached data · retrying…"
        case .middleware, .none:
            return "Can't reach the server · showing last known data · retrying…"
        }
    }
}

/// Inserts the disconnected banner directly under a screen's navigation bar
/// (above its content), so it never overlaps the toolbar. Apply to the content
/// inside each screen's NavigationStack/NavigationView.
extension View {
    func connectionBanner() -> some View {
        safeAreaInset(edge: .top, spacing: 0) { DisconnectedBanner() }
    }
}
