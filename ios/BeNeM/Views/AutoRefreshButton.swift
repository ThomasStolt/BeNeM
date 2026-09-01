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

// MARK: - ConnectionMonitor

/// Which hop is down, for the hop-aware banner: poll failed (no HTTP response,
/// or a non-2xx — a reverse proxy answering for a dead middleware app) →
/// `.middleware`; poll ok but the payload says `bhnm.reachable == false`
/// → `.bhnm`.
enum DownHop { case none, middleware, bhnm }

/// The ONE global connectivity poller — independent of any screen. Every
/// ~30 s (configurable) it hits the middleware's fast diagnostics endpoint,
/// which serves a BHNM health probe run once per server ON THE MIDDLEWARE
/// (never per client). Reaching the endpoint ⇒ middleware up; the response's
/// `bhnm.reachable` ⇒ BHNM up/down. The same poll result feeds the sheet.
/// Foreground-only: polling pauses while the app is backgrounded/inactive and
/// resumes with an immediate poll on foreground.
@MainActor
final class ConnectionMonitor: ObservableObject {
    static let shared = ConnectionMonitor()
    @Published private(set) var status: ConnectionStatus = .unknown
    @Published private(set) var downHop: DownHop = .none
    @Published private(set) var lastResult: DiagnosticsResult?

    /// Seconds between polls — overridable via UserDefaults "diag_poll_interval"
    /// (no UI; `defaults write` / a future setting), default 30.
    private var pollInterval: Double {
        let v = UserDefaults.standard.double(forKey: "diag_poll_interval")
        return v > 0 ? v : 30
    }

    private var service: NetreoAPIService?
    private var pollTask: Task<Void, Never>?
    private var isActive = true
    private init() {}

    /// (Re)start the poller for the active server — call on startup and on every
    /// server switch. `nil` stops it (unconfigured → grey).
    func configure(_ service: NetreoAPIService?) {
        self.service = service
        guard service != nil else {
            stopPolling()
            status = .unknown; downHop = .none; lastResult = nil
            return
        }
        if status == .unknown { status = .checking }   // amber until the first result
        restartPolling()
    }

    /// Foreground-only polling: ContentView reports scenePhase changes here.
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active { restartPolling() } else { stopPolling() }
    }

    /// Immediate re-check (the sheet's pull-to-refresh, foreground resume).
    func pollNow() async { await pollOnce() }

    private func restartPolling() {
        stopPolling()
        guard isActive, service != nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
                guard let interval = self?.pollInterval else { return }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func pollOnce() async {
        guard let service else { return }
        let r = await service.fetchDiagnostics()
        lastResult = r
        if !r.reachedMiddleware {
            status = .disconnected; downHop = .middleware
        } else if let reachable = r.diagnostics?.server.bhnm.reachable {
            status = reachable ? .connected : .disconnected
            downHop = reachable ? .none : .bhnm
        } else {
            // Middleware up but its monitor has no verdict yet (startup window
            // ≤ one probe interval) — stay amber rather than claim a state.
            status = .checking; downHop = .none
        }
    }
}

/// Drives the single global diagnostics sheet (presented once from ContentView).
@MainActor
final class DiagnosticsPresenter: ObservableObject {
    static let shared = DiagnosticsPresenter()
    @Published var isPresented = false
    private init() {}
    func present() { isPresented = true }
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blinkOn = true

    // Blink is reserved for truly-disconnected; `.checking` shows amber but
    // static. Reduce-motion suppresses the blink entirely (static red).
    private var shouldBlink: Bool {
        !reduceMotion && status == .disconnected
    }

    var body: some View {
        ChainIcon(color: status.color, broken: status == .disconnected)
            .opacity(shouldBlink ? (blinkOn ? 1.0 : 0.15) : 1.0)
            .contentShape(Rectangle())
            .onTapGesture { DiagnosticsPresenter.shared.present() }
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

    private var progress: Double { max(0, (interval - elapsed) / interval) }

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
                    .scaleEffect(0.8)
            } else {
                Text(countdownLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .kerning(-0.3)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 30, height: 30)
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
