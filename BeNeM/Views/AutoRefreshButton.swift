import SwiftUI
import Combine

/// A toolbar button that shows a circular countdown ring and auto-refreshes every `interval` seconds.
/// Tapping the button triggers an immediate refresh and resets the countdown.
struct AutoRefreshButton: View {
    let interval: Double          // seconds between auto-refreshes
    let isLoading: Bool
    let action: () async -> Void

    @State private var elapsed: Double = 0
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var progress: Double { min(elapsed / interval, 1.0) }

    var body: some View {
        Button {
            elapsed = 0
            Task { await action() }
        } label: {
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 2)
                    .frame(width: 26, height: 26)

                // Countdown ring — depletes as time passes toward next refresh
                Circle()
                    .trim(from: 0, to: CGFloat(1 - progress))
                    .stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: 26, height: 26)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: elapsed)

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                }
            }
        }
        .disabled(isLoading)
        .onReceive(ticker) { _ in
            elapsed += 1
            if elapsed >= interval, !isLoading {
                elapsed = 0
                Task { await action() }
            }
        }
    }
}
