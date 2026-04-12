import SwiftUI
import Combine

// MARK: - ConnectionStatus

enum ConnectionStatus {
    case unknown, checking, connected, disconnected

    var color: Color {
        switch self {
        case .unknown:      return .gray
        case .checking:     return .orange
        case .connected:    return Color(red: 0.13, green: 0.55, blue: 0.13)
        case .disconnected: return .red
        }
    }
}

// MARK: - ChainIcon

/// Two interlocked (or separated) rounded-rectangle chain links.
struct ChainIcon: View {
    let color: Color
    let broken: Bool

    var body: some View {
        ZStack {
            link.offset(x: broken ? -7 : -4)
            link.offset(x: broken ? 7 : 4)
        }
        .frame(width: 26, height: 22)
    }

    private var link: some View {
        RoundedRectangle(cornerRadius: 3)
            .stroke(color, lineWidth: 2.5)
            .frame(width: 8, height: 13)
            .rotationEffect(.degrees(45))
    }
}

// MARK: - ConnectionBadgeButton

/// Tappable chain-link connection indicator. Blinks when connecting or disconnected.
struct ConnectionBadgeButton: View {
    let status: ConnectionStatus
    let onRetry: () -> Void

    @State private var blinkOn = true

    private var shouldBlink: Bool {
        status == .checking || status == .disconnected
    }

    var body: some View {
        ChainIcon(color: status.color, broken: status == .disconnected)
            .opacity(shouldBlink ? (blinkOn ? 1.0 : 0.15) : 1.0)
            .contentShape(Rectangle())
            .onTapGesture { onRetry() }
        .task(id: status) {
            blinkOn = true
            guard shouldBlink else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 700_000_000)
                blinkOn.toggle()
            }
        }
    }
}

// MARK: - AutoRefreshButton

/// A toolbar button that shows a circular countdown ring and auto-refreshes every `interval` seconds.
/// Tapping the button triggers an immediate refresh and resets the countdown.
struct AutoRefreshButton: View {
    let interval: Double          // seconds between auto-refreshes
    let isLoading: Bool
    let action: () async -> Void

    @State private var elapsed: Double = 0
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var progress: Double { min(elapsed / interval, 1.0) }

    private var countdownLabel: String {
        let remaining = max(0, interval - elapsed)
        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return "\(minutes):\(String(format: "%02d", seconds))"
    }

    var body: some View {
        ZStack {
            // Countdown ring — hidden while loading
            if !isLoading {
                Circle()
                    .stroke(Color(.systemGray4), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
            }

            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            } else {
                Text(countdownLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(.systemGray3))
            }
        }
        .frame(width: 32, height: 32)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isLoading else { return }
            elapsed = 0
            Task { await action() }
        }
        .onReceive(ticker) { _ in
            elapsed += 1
            if elapsed >= interval, !isLoading {
                elapsed = 0
                Task { await action() }
            }
        }
    }
}
